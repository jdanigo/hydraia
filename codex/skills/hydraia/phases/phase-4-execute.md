## Phase 4 — Execution (delegated → Sonnet 5)

### Executor customization (read before dispatch)

Read the effective customize config, merging by precedence: repo
`<artifacts-base>/custom/hydraia.toml` > global `~/.config/hydraia/custom/hydraia.toml`
> shipped `skills/hydraia/customize.toml` (merge rules in the file header). If any
override is unparseable, warn and fall back to the shipped defaults.

- `[executor].model` — dispatch each `hydraia-executor` on this model, passing it
  as the model at launch (overriding the agent's `sonnet` frontmatter default).
  Default `sonnet`. Drop to `haiku` for mechanical work when a repo opts in.
- `[executor].handoff` — if non-empty, follow it verbatim as the dispatch recipe
  (substitute `{task_block}` and `{graph_context}`) instead of the default subagent
  dispatch below — e.g. route the task to an external CLI via bash. It still runs
  under the same blast-gate and spec-drive hooks.

The wave caps, watchdog, and verification below are unchanged by customization.

Use **subagent-driven-development**. Dispatch a fresh `hydraia-executor` subagent
per task (these run on Sonnet 5). Give each exactly the context it needs from the
plan and the graph — never your session history. Execute all tasks continuously.
TDD where the plan calls for it. Commit frequently.
Tag each executor dispatch's description with a machine-readable `[task:<slug>]` marker
(the same `<slug>` the executor uses for its heartbeat file). The circuit-breaker hook
(`hooks/agents.sh`) reads this tag to count per-task attempts; without it the breaker
falls back to a description hash and still counts, but the tag makes escalation precise.

**Dispatch in bounded waves — never fan out the whole plan at once.** Each subagent
loads its own context, so N parallel agents multiply token cost by ~N. Send at most
`HYDRAIA_MAX_CONCURRENT` (default 6) executors at a time; as they finish, send the
next wave. A whole run is also capped at `HYDRAIA_MAX_AGENTS` (default 30) total
dispatches. These limits are enforced at runtime by the agent-budget hook
(`hooks/agents.sh`) — a `Task` call past the cap is BLOCKED, not throttled silently,
so respect the waves rather than firing 100 tasks and retrying blocked ones. If a
plan truly needs more than the ceiling, that is the human's call to raise
(`export HYDRAIA_MAX_AGENTS=…`), never a reason to loop on blocked dispatches. This
is also why Phase 3 plans use coarse, consolidated tasks — a plan of 100+ atomic
tasks is a planning smell, not a parallelism win.

**Verify each task actually landed before dispatching the next wave (do not trust the
report alone).** A subagent's summary is not proof — a task can report "done" or
"delegated" without having committed (this failure is real, not hypothetical). After
each wave, confirm the work exists in git before moving on: `git log --oneline -<n>`
shows the expected commits and `git status --porcelain` is clean (or shows only the
next wave's territory). If a claimed commit is missing, re-dispatch that one task —
never build the next wave on an unverified one. The check costs a few tokens; a
corrupted run caught at Phase 6 costs far more.

**Hung-agent watchdog — heartbeats + auto re-push (no manual nudging).** A real run
had executors stall silently and need a manual "keep going" message. Detect and
recover automatically at every wave boundary:
- Each executor writes a heartbeat on start and after each commit to
  `docs/hydraia/.heartbeats/<task-slug>` (its agent definition does this). The file's
  epoch mtime is the liveness signal; the directory is gitignored.
- When a wave returns, for every task in it, confirm progress: a **commit exists**
  (the git check above) OR its **heartbeat is fresh** (mtime within
  `heartbeatStaleSecs`, default 300). A task with neither is treated as **hung/failed**
  and is **automatically re-dispatched ("pushed")** — you do not wait for the human to
  poke it. Re-push the SAME task with the same context, up to `maxTaskRetries`
  (default 2). Log each retry in the run log.
- If a task exhausts its retries without a commit, that is a genuine BLOCKER: stop and
  surface it with the evidence (no commit, stale heartbeat, retry count) — never spin
  on it silently. Bounded waves (`HYDRAIA_MAX_CONCURRENT`) keep a stall from taking the
  whole plan down with it.
  The attempt cap is now also a RUNTIME guarantee: `hooks/agents.sh` blocks the
  (maxTaskRetries+1)-th dispatch of the same `[task:<slug>]` and tells you to stop. When
  you see that block, do NOT keep retrying — read the ledger (`<base>/.agents/ledger.json`),
  surface the task as a blocker with its attempt count and the missing-commit evidence, and
  escalate to the human.

**Frontend rule (hard gate, not optional):** any task that creates or changes UI —
markup, components, styles, or templates — the executor implements the *UX / visual
direction* the task carries from the Phase 2 spec (style, palette, type scale, spacing,
interaction states) EXACTLY, then verifies the WCAG accessibility floor. This is not
conditional on the executor self-classifying the task as "UI enough" — if the task
touches anything a user sees, the gate applies. Writing markup first and styling later
is the failure this prevents. The executor does NOT invoke ui-ux-pro-max itself —
executor subagents have no Skill tool, so the visual system is decided ONCE at design
time (Phase 2, below) and inlined into every UI task; the spec is the executor's single
source of truth. A UI task that reaches Phase 4 with no visual direction is a plan
defect — the executor reports it BLOCKED rather than inventing a generic look.

**Auto-commit mode (from the Storage & commit gate):**
- **Auto-commit ON (default):** each executor commits its task with a clean message
  (no attribution trailer — see the hard rule above). Unchanged behavior.
- **Auto-commit OFF:** executors write code and run tests but **do not commit** — they
  leave all changes in the working tree and report files touched + test result. Tell
  each dispatched executor explicitly not to commit. Liveness then rests on the
  heartbeat alone (the "commit exists OR heartbeat fresh" check degrades gracefully to
  heartbeat-only), so heartbeats are mandatory in this mode. **Phase 5** reviews the
  working-tree diff (`git diff` including staged + unstaged) instead of branch commits —
  both passes and the security gate see the full uncommitted diff. **Phase 6** runs the
  real tests and confirms against the spec as usual, then reports "N files changed,
  uncommitted — commit them yourself"; it makes no commit. `/hydraia:resume` in this
  mode falls back to the run-log phase checklist + heartbeats for progress (it cannot
  reconstruct per-task state from git); the spec-drive gate and `.active-plan` are
  commit-independent and work the same.

**Stack best-practices rule:** before writing non-trivial code, the executor
consults the matching patterns/standards skill so idioms are right the first time —
**react-patterns** (React), **golang-patterns** (Go), **springboot-patterns**
(Spring Boot), **python-patterns** (Python), **node-patterns** (Node/TypeScript
backends), **dotnet-patterns** (C#/.NET), and **coding-standards** (cross-cutting
naming, structure, and clean-code conventions for any stack).

**QA automation rule:** plan tasks that implement QA cases are dispatched to the
`qa-automation` agent (mode: implement) instead of a generic executor. It detects
the repo's existing test framework from evidence (config files, existing tests) —
if none exists it reports BLOCKED, because choosing a framework is a plan-level
decision. It names every test with its case ID (e.g. `TC-1.1`) and fills the
matrix `Test ref` column with `path/to/test:line` per case, or
`manual — <reason>` for cases that cannot be automated.



## NEXT

Read fully and follow `phases/phase-5-review.md`.
