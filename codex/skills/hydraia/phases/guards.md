## Start-of-run guards (before Phase 0)

**Language gate (first action, before anything else).** Call the
`AskUserQuestion` tool once to ask which language the user wants **replies** in —
options: `English` and `Español`. Use the answer for all user-facing communication
for the rest of the run: narration, the Phase-1 clarifying question, review
findings, and the final summary. If the user dismisses the question, default to the
language they wrote their request in. This choice does NOT change code, commit
messages, spec/plan files, or the credits line — those stay as-is (English,
portable). Ask this exactly once per run; `/hydraia:resume` inherits the prior
run's choice if the run log records it, otherwise re-asks.

**Storage & commit gate (second action, right after the Language gate).** Two
`AskUserQuestion` prompts, asked once per run (like the language gate). Do NOT
recommend an option — the user chooses; these are privacy/workflow decisions, not
quality ones.

1. **Artifacts location** — "Where should Hydraia store its artifacts (specs, plans,
   QA, run logs, and pipeline state)?"
   - `In the repo` → `<repo>/docs/hydraia/` (tracked by git — the default).
   - `Outside the repo` → `~/.config/hydraia/artifacts/<repo-slug>/` (on this machine,
     never committed, no `.gitignore` edits). `<repo-slug>` = repo dir basename + `-`
     + the first 6 hex of a hash of the absolute repo root.
2. **Auto-commit** — "Auto-commit each task as Hydraia goes?"
   - `Yes` → commit per task (the default).
   - `No` → executors do NOT commit; all changes are left in the working tree for you
     to commit as you like.

After the answers: persist both to the GLOBAL config `~/.config/hydraia/config.json`
under `repos["<absolute repo root>"]` — do NOT hand-edit that JSON. Use the
`hy_config_set` helper in `hooks/config.sh`, which merges into the file atomically,
preserving every other repo and key:

```bash
bash -c '. "$CLAUDE_PLUGIN_ROOT/hooks/config.sh"
hy_config_set "<absolute repo root>" artifactsDir "<docs/hydraia | absolute external path>"
hy_config_set "<absolute repo root>" autoCommit "<true|false>"'
```

Pass `artifactsDir docs/hydraia` (or skip it) for in-repo; the absolute external path
otherwise. Then create the external dir (with `specs/ plans/ qa/ runs/`) if chosen, and
use the resolved absolute base as **the artifacts base** for the whole run (see
*Artifacts base* below). If the user dismisses either question, default to in-repo + auto-commit
ON (behavior identical to prior versions). `/hydraia:resume` inherits both from the
run log if recorded, otherwise re-asks. The hooks read the same choice via
`hy_artifacts_dir` / `hy_repo_config` in `hooks/config.sh`, so the gate, agent caps,
plan-check, and summary all resolve to the same base — in-repo or external.

**Commit attribution (hard rule, every commit this pipeline makes).** Hydraia commits
carry a clean, conventional message and NOTHING else. NEVER add a `Co-Authored-By`
trailer for Claude, Hydraia, or any AI; never add a `🤖 Generated with…` line; never
add any AI-attribution footer. This overrides any default harness commit-trailer
behavior and applies everywhere a commit is made — executor per-task commits,
qa-automation, spec/plan commits, Level-1 runs, and any final commit. (The run-summary
credits line is separate and unaffected — it is printed to the user, not written into
git.)

**Artifacts base (path resolution).** Wherever this skill names a `docs/hydraia/<sub>`
path (specs, plans, qa, runs, `.active-plan`, `.quick-approved`, `.run-complete`,
`.heartbeats`, config), that path is
relative to the **resolved artifacts base** from the Storage gate — `docs/hydraia/` in
the repo by default, or the external dir when chosen. Resolve the base once at the
gate and use it for the rest of the run; when dispatching a task to a sub-agent, pass
the absolute base so the executor writes its heartbeat and any artifacts to the right
place. The shown `docs/hydraia/...` paths below are the default; substitute the
resolved base when the user chose external storage.

**Model guard.** Check the model this session is running on. If it is NOT an Opus model
(any current generation), print this once, then continue anyway — never block:

> ⚠️ Hydraia runs best with the **main session on Opus**. Opus plans and judges; it
> delegates execution to Sonnet sub-agents on its own — you don't switch models yourself.
> Continuing anyway.

**Two modes: design dialogue, then continuous execution.** The pipeline has a
conversational half and an autonomous half, split at the frozen plan.

- **Phases 1–3 (think → design → plan) are INTERACTIVE.** This is where design
  happens, so interaction is expected — not a violation. Run brainstorming as a real
  dialogue: ask clarifying questions (one at a time), propose 2–3 approaches with a
  recommendation, present the design, and get the user's approval before writing the
  spec. Do not compress this into a single question or skip it to "get to the code" —
  a design reached without dialogue is the exact failure this pipeline exists to
  prevent.
- **Phases 4–6 (execute → review → verify) are CONTINUOUS.** Once the plan is frozen,
  run every remaining phase to completion **without pausing**. Never insert "should I
  continue?" checkpoints between execution phases, never stop with the plan
  half-executed. The ONLY permitted stop here is a genuine BLOCKER a sub-agent cannot
  resolve — surface it, don't silently spin.

In short: **pause to get the design right; never pause once you're building it.**
(`/hydraia:plan` stops at the boundary — after Phase 3 — so you can review before the
autonomous half begins.)

**Ceremony follows the level — never your own shortcut.** Phase -1 picks the level
(1 Light / 2 Standard / 3 Deep) from stated facts by rule. Within a level, run every
step it lists: token cost or "this looks trivial" is NEVER a reason to skip, compress or
inline a step on your own. Wanting less ceremony than the rule gives is the human's call
(they say so, or pin `[pipeline].level`). A runtime gate (`hooks/gate.sh`) enforces the
core of this — editing source before a plan (or a Level-1 spec-plan) is armed is blocked.

**Convergence — how a run ends.** A run ends in exactly one of: `DONE`,
`DONE_WITH_FOLLOWUPS` (deferred items recorded in `<base>/deferred-work.md`), or
`BLOCKED(<condition + evidence>)`. BLOCKED is a normal, expected outcome — surfacing a
stuck point to the human in minutes beats hours of patching. The runtime enforces it: the
verify-loop breaker (same failure 2× → NO PROGRESS, 3× → STALLED), the fix budget
(`[fix:<slug>]` dispatches), and the review-cycle cap all end in BLOCKED, never in "try
again". Never clear a breaker's state yourself — that is the human's action.

## NEXT

Read fully and follow `phases/phase-0-context.md`.
