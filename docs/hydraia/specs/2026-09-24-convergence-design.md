# Convergence — bounded fix loops, evidence-bound triage, plan-as-contract (v0.22.0)

Status: approved (design dialogue in session 2026-09-23/24) · Route: feature · Tier: L
(touches hooks + every execution/review phase).

<frozen-after-approval reason="human-owned intent — do not modify unless the human renegotiates">

## Intent

**Problem.** On Opus 5 / 5.5 the pipeline stops converging. Runs spend hours in a
`fix → test → fix` loop, invent defects, "fix" pre-existing failures, and widen scope
without asking — burning tokens fast. Root causes found in the code:

1. **Phase 6 has no attempt ceiling.** "If a build or test fails, the run is not done —
   fix and re-run" (also QA matrix, E2E). The only exit is BLOCKER, which the model avoids.
2. **The circuit breaker counts the wrong thing.** `agents.sh` counts `hydraia-reviewer`
   dispatches and `[task:]` executor retries. Phase 5/6 fixes are done by the
   orchestrator inline (Edit + Bash) — invisible to every counter.
3. **The orchestrator fixes with a saturated context** — where it misremembers code.
4. **No test baseline.** Pre-existing / flaky / hung failures are attributed to the
   change and "fixed" — scope creep and invented errors in one move.
5. **Too many finding generators, no severity cut-off**; "fix everything
   correct-and-material" leaves "material" to the model. Fixes grow code, code grows
   findings.
6. **No no-progress detection** — the same failure after N different fixes is a wrong
   hypothesis, not a bug.
7. **Hung test commands look like failures** (a backgrounded suite blocked a run 14 min).
8. **Plans carry model-written verbatim code for every task** ("the executor copies; it
   does not compose") — code written without a compiler, where invented APIs are born.
9. **Prompt tuned against Opus 4.8's defect (skipping steps).** Anti-laziness
   compensations ("second pass regardless", "not done until green", 46 absolute
   imperatives) overshoot on persistent, literal 5.x models.

**Approach.** Add convergence *semantics* (triage verdicts + 4 routes,
carried triage log, spec change log with KEEP / known-bad, persisted loop counter,
stop-and-replan triggers, blind + evidence-bound review, explicit terminal statuses,
plan-as-contract) and enforce the load-bearing ones with Hydraia *runtime hooks* —
prose-only rules are exactly what fails on 5.x.

## Boundaries & Constraints

**Always:**
- Every stop condition that matters is an exit code, not a paragraph.
- Pre-existing failures are **asked about**, never silently ignored or silently fixed
  (options: record-and-continue / fix-first as separate task / stop).
- The security floor is unchanged and not customizable.
- Hooks fail **open** on internal error (never wedge a run) — except where they already
  fail closed (agents.sh lock).
- Backward compatible: plans without `**Files:**` declarations get no scope gate; all
  new caps have config keys + env overrides; `HYDRAIA_ALLOW_DIRECT=1` lifts everything.
- Phase `.md` files stay byte-identical with `codex/skills/hydraia/phases/`.
- No AI attribution trailer in commits (repo rule).

**Never:**
- Never let a hook edit or rewrite a tool call's input (block + explain only).
- Never auto-fix a failure that the baseline shows as pre-existing.
- Never drop a verified high-severity security finding to `defer`.
- Never make the model the one who raises a ceiling.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected |
|---|---|---|
| Same failure 2× | identical normalized failure signature seen twice in a run | PostToolUse feedback: NO PROGRESS warning (exit 2, stderr) |
| Same failure 3× | signature count reaches `maxSameFailure` (3) | STALLED recorded; message to surface BLOCKED |
| Verify while stalled | any verify command after STALLED | PreToolUse BLOCK (exit 2) |
| Pre-existing failure | failure lines ⊆ baseline set | note "pre-existing — do not fix", not counted |
| Different failure | new signature | counted from 1, no message |
| Background suite | verify cmd with `run_in_background:true`, no `timeout`/`gtimeout` wrapper | PreToolUse BLOCK |
| Foreground suite | verify cmd, foreground | allowed (Bash tool timeout applies) |
| Non-verify cmd | `ls`, `git status` | ignored |
| No active plan | any | verify loop state not touched; background guard still applies in opted-in repo |
| Bypass | `HYDRAIA_ALLOW_DIRECT=1` | everything allowed |
| Fix dispatch | Task desc `[fix:<slug>]` | per-slug cap `maxFixAttempts` (2) + run cap `maxFixDispatches` (6) |
| Edit outside plan | plan declares Files; target not declared, not lockfile/artifact/md | `scopeGate=strict` BLOCK; `warn` note; `off` allow |
| Plan without Files | legacy plan | scope gate inactive |
| Arm plan missing contract | a task lacks `**Files:**` or a `Verify` line | plancheck BLOCK at arm |
| `## Task` headings | plan uses level-2 task headings | plancheck scans them (bug fix) |
| Baseline | `baseline.sh -- <cmd>` | runs with timeout, writes `<base>/.baseline-failures`, prints CLEAN / N pre-existing / TIMEOUT |
| Opus executor | Task `hydraia-executor`, `model: "opus"`, routing ≠ max-quality | agents.sh BLOCK (opus gate) |
| Opus executor, max-quality | same, `<base>/.agents/routing` = `max-quality` | allowed |
| Inherited Opus | Task `general-purpose`/`Explore` with no `model` | BLOCK — pass `model: "sonnet"` (or haiku) |
| Judge on Opus | `hydraia-reviewer` / `security-reviewer`, any model | allowed |
| Pinned sonnet agent | e.g. `typescript-reviewer`, no `model` | allowed (frontmatter pin) |
| Level auto-select | 1-file typo fix, no security surface | Level 1 announced, no question |
| Level forced up | change touches `auth/**` | Level ≥ 2 regardless of size |

</frozen-after-approval>

## Code Map

- `hooks/agents.sh` — Task PreToolUse caps + circuit breaker ledger. Add `fix` role
  (`[fix:<slug>]` tag, checked before sub_type classification).
- `hooks/verifyloop.sh` — **new**. PreToolUse(Bash): background-verify guard + stalled
  block. PostToolUse(Bash) + PostToolUseFailure(Bash): failure signature ledger in
  `<base>/.agents/verify.json` (run id = `.active-plan` mtime, same as agents.sh).
- `hooks/baseline.sh` — **new**. Phase-0 helper; python `subprocess` timeout (macOS has
  no `timeout`); normalized failure lines → `<base>/.baseline-failures`.
- `hooks/lib/failsig.py` — **new**. Shared normalizer/signature (used by verifyloop +
  baseline so both normalize identically).
- `hooks/blastgate.sh` — add plan-scope gate after the denylist, before maxFiles.
- `hooks/plancheck.sh` — heading regex `^#{2,3} +Task`; contract rule (Files + Verify).
- `hooks/hooks.json` — register verifyloop on PreToolUse Bash, PostToolUse Bash,
  PostToolUseFailure Bash (event confirmed in use by installed plugins on CC 2.1.278).
- `hooks/doctor.sh` — list new hooks.
- `hooks/tests/test-*.sh` — new tests; `run.sh` already pins `HYDRAIA_DOCS_DIR`.
- Payload facts (verified from real transcripts): Bash success `tool_response` =
  `{stdout, stderr, interrupted, isImage, noOutputExpected}` (no exit code); failure
  surfaces as `PostToolUseFailure` with `error` = `"Error: Exit code N\n…"`. Parse both
  shapes, plus a string `tool_response` beginning with `Error:`.
- Prose: `SKILL.md`, `phases/{guards,model-policy,phase-0-context,phase-3-plan,
  phase-4-execute,phase-5-review,phase-6-verify}.md`, `agents/hydraia-executor.md`,
  `agents/hydraia-reviewer.md`, `customize.toml`, `loop-budget.md`, `commands/review.md`,
  README (EN/ES), CHANGELOG, `.claude-plugin/plugin.json`.

## Design

### D1 — Failure signature + verify loop (runtime)
Verify command = default regex (npm/pnpm/yarn/bun test|build|lint|typecheck, vitest,
jest, pytest, tsc, go test|build|vet, cargo test|build|check|clippy, dotnet test|build,
mvn, gradle, ng test|build, make test|check|build, rspec, phpunit, playwright,
`python -m pytest|unittest`, `bash …tests/run.sh`), overridable by `verifyPattern` /
`HYDRAIA_VERIFY_PATTERN`.

Signature = sha1 of the sorted unique set of *failure lines* (lines matching
fail/error/✗/✕/panic/traceback/assert/exception/expected, excluding the harness's
`Error: Exit code N` wrapper), after stripping ANSI, durations, timestamps, hex
addresses and temp paths. No failure lines → last 15 non-empty normalized lines.

Ledger counts occurrences per signature per run (occurrence count, not "consecutive",
so parallel executors interleaving successes cannot mask a thrash). count==2 → NO
PROGRESS warning; count≥`maxSameFailure` (3) → `stalled`. Stalled blocks further verify
commands (PreToolUse) until the human clears (`rm <base>/.agents/verify.json` or bypass).
PostToolUse cannot un-run a command, so it delivers feedback via exit 2 + stderr.

### D2 — Background guard (runtime)
A verify command with `run_in_background: true` must be wrapped in `timeout N` /
`gtimeout N`; otherwise BLOCK. Foreground calls are already bounded by the Bash tool
timeout. Applies in any opted-in repo (not only during a run).

### D3 — Baseline + ask (Phase 0)
Phase 0 runs `baseline.sh -- <the project's test command>`. On `CLEAN`: continue. On
pre-existing failures or `TIMEOUT` (hung suite): **AskUserQuestion** — record & continue
(failures appended to `deferred-work.md`, verifyloop treats them as pre-existing) /
fix first as a separate task / stop. Dirty working tree or branch mismatch → ask too.

### D4 — Fix dispatches are counted (runtime)
Phase 5/6 fixes go to an executor, never the orchestrator. Prefer re-engaging the same
executor (SendMessage) with "run only the tests covering the files you edit"; otherwise
dispatch a fresh executor tagged `[fix:<slug>]`. agents.sh caps per slug
(`maxFixAttempts`, 2) and per run (`maxFixDispatches`, 6).

### D5 — Plan as contract + scope gate
Every task declares `**Files:**` (paths/globs/dir prefixes) and a `Verify` line (exact
command + expected result). plancheck blocks arming without them. Task format by
`Exec class`: `mechanical` keeps verbatim literal content; `logic`/`ui` carry a
**contract** — intent, Code Map (verified `file:line`), Always/Never boundaries, I/O
matrix rows, Verify — and the executor writes the code against the real repo with the
compiler in the loop. Self-containment rule unchanged (never point at the spec).
Scope gate: Edit/Write outside the union of declared Files (plus lockfiles, artifacts,
markdown) → BLOCK (`scopeGate=strict`, default) → the executor reports
`NEEDS_DECISION`; the human amends the plan.

### D6 — Evidence-bound triage in Phase 5
Verify each finding at its line → one verdict: `high`/`medium`/`low`/`false`/
`maybe-false`. Reject `false`; reject `low` whose fix adds complexity. Group by root
cause. Route: `intent_gap` (ask human) / `bad_spec` (revert, amend the non-frozen spec,
log KEEP + known-bad in Spec Change Log, re-derive) / `patch` (trivial, via executor) /
`defer` (pre-existing, unverified, or agent-context edits → `deferred-work.md`).
Cascade: intent_gap/bad_spec make lower routes moot. **Review Triage Log** rows are
`carried` on loopback — never re-verified or re-patched. Only verified high/medium
enter the fix loop; `low` patches only if trivial. Loop counter persisted in the run
log; >`maxReviewCycles` → BLOCKED. Reviewers: evidence rules (never assert what you did
not verify; drop ungrounded), the spec is testimony not evidence (claims check).

### D7 — Phase 6 bounded + terminal statuses
Mechanical gate first. Failures in the baseline are not this run's to fix. A failing
check gets at most the fix budget (D4) and the verify ledger (D1); then the run ends
`BLOCKED(evidence)`. Terminal statuses: `DONE` / `DONE_WITH_FOLLOWUPS`
(deferred-work non-empty) / `BLOCKED(condition)`. `repo-scan`/`production-audit` are
report-only except high-severity secrets / vulnerable deps. Regression tests only for
fixed high/medium defects.

### D8 — Executor stop-and-replan
The executor stops and returns `NEEDS_DECISION` (not improvisation) when: the task
omits something the user would notice; it would do something irreversible not in the
task; the change grows beyond the task's Files; the Verify step cannot pass honestly.

### D9 — Prompt diet for current Opus
Model policy/guard become generation-agnostic ("Opus, current generation"). Remove
compensations that overshoot on 5.x: Phase-3 Pass B runs only if Pass A made a material
revision; replace "not done until green" loops with D7. Add one always-loaded
**Convergence contract** block to `SKILL.md`.

### D10 — Thin orchestrator (context hygiene)
Added 2026-09-24 (human request: "the context fills up badly"). Executors already get a
clean context per task; the *orchestrator* is what fills. Fixes:
- Phase 4 dispatch carries only `plan path + task heading + artifacts base + model` —
  never the pasted task body; the executor reads its task from the plan file.
- Reviewers read the diff from a temp file path (never pasted) and return compact
  findings (`file:line — claim — evidence`, ≤ ~15 lines each).
- Investigation fan-out returns short summaries only.
- Fixes go to executors (D4), never inline.
- At plan freeze, offer **Continue here** vs **Continue in a fresh session**
  (`/hydraia:resume` picks up at Phase 4 from the frozen plan + run log).

### D11 — Opus only judges (model routing + runtime gate)
Added 2026-09-24 (human: "Opus is only for reviewing the task"). Found: 16/27 agents pin
`model: opus`, and unpinned generic agents (`Explore`, `general-purpose`, `Plan`,
`claude`) inherit the parent's Opus. New policy: Opus = the orchestrator session +
`hydraia-reviewer` (the judge) + `security-reviewer`. Every other agent pins `sonnet`.
Runtime: `agents.sh` blocks a Task whose effective model is Opus (explicit
`tool_input.model` contains `opus`, or no model on an unpinned generic type) unless the
role is a judge, or `<base>/.agents/routing` = `max-quality` (written by the Phase-3
picker) for executors, or `HYDRAIA_ALLOW_OPUS=1`. Config key `opusGate` (strict|warn|off,
default strict).

### D12 — Three auto-selected levels (replace four questions)
Added 2026-09-24 (human: "full ceremony for simple tasks; offer 3 review levels,
auto-analyzed, no added complexity"). Today Phase -1/3 ask up to four separate
questions (work mode, tier S/M/L, quick-mode, review depth). Collapse into ONE
**level**, auto-derived from three facts (a route gate) and announced in one line —
no question; the human overrides by saying so or via `customize.toml [pipeline].level`.
Agile (epic-sized) stays its own mode.

| Level | When (all must hold for 1; any trigger for 3) | Ceremony |
|---|---|---|
| **1 Light** | no intent gaps, nothing irreversible, ≤3 files, no new public surface, no security surface, no `gate.yaml` overlap | intent + notes spec (no plan file), 1 Sonnet executor, Verify, 1 judge pass (hydraia-reviewer) + `security-scan`, DONE |
| **2 Standard** (default) | anything between | spec + plan-contract, Sonnet executors, judge + security floor (diff-scoped), triage D6, Phase 6 mechanical gate |
| **3 Deep** | security surface, `gate.yaml` overlap, irreversible ops, new service, >15 files | today's full ceremony (threat model, adversarial pass, full panel, QA/E2E) |

Security surface or denylist overlap forces ≥2 (rule, not judgment). The security
floor is never removed — Level 1 keeps `security-scan` + the judge. Unknown/ambiguous
→ Level 2. The review-depth picker (Full/Lite/Custom) is derived from the level
(3=Full, 2=Lite+diff-scoped, 1=judge-only) and no longer asked. `autoTier=off` → Level 2.

## Threat model (delta)
- Hooks read untrusted tool output (test logs) → only hashed/normalized, never executed;
  regex applied line-by-line with bounded input (last 200 KB).
- A model could evade the verify ledger by varying commands → signature is on failure
  output, not the command.
- A model could self-clear state by deleting `verify.json` → same trust boundary as
  every existing marker (documented human action; Phase prose forbids it); logged by
  delivery review. Not a security boundary, a convergence aid.
- Scope gate false positives → `warn` mode + bypass; lockfiles/artifacts/md allowlisted.

## Verification
- `bash hooks/tests/run.sh` — all pass (existing + new).
- `diff -r skills/hydraia/phases codex/skills/hydraia/phases` — empty.
- `python3 -c 'import json;json.load(open("hooks/hooks.json"))'` — valid.
- `bash -n hooks/*.sh` — syntax OK.

## Spec Change Log

- 2026-09-24 — **Review floor composition (D12 follow-through).** Trigger: Level 1 must not
  pay two Opus reviewers for a change that by rule has no security surface. Amended: the
  floor is `hydraia-reviewer` + `security-scan` at every level; `security-reviewer` +
  `silent-failure-hunter` join at Levels 2–3; `code-reviewer` leaves the floor (the judge
  covers correctness). Known-bad state avoided: a floor so heavy that Level 1 is not light.
  KEEP: no path removes security review from a change that touches security surface — such
  a change is Level ≥2 by rule, and the triage table forces it.

## Review Triage Log

Judge pass (hydraia-reviewer) on the hook diff — 8 findings, all verified by reproduction:

| # | Verdict | Finding | Route / fix |
|---|---|---|---|
| 1 | high | verify regex matched tool names mid-command; bare `Error: Exit code 1` shared one signature → false STALLED | patch — segment-anchored verify detection; wrapper dropped, empty evidence records nothing |
| 2 | high | count/summary lines in the signature → pre-existing failure lost on a test-count change | patch — summary lines excluded from signature and baseline |
| 3 | high | scope gate dropped Files after a blank line, `Create: path` spans, dirs without `/` | patch — region parser + span keyword + existing-dir prefix |
| 4 | medium | `## Tasks` / fenced headings treated as tasks; strict Verify spelling | patch — `Task <n>` headings, fences skipped, lenient Verify |
| 5 | medium | multi-line description corrupted `subagent_type` → judge blocked | patch — fields whitespace-normalized |
| 6 | medium | apostrophe in heredoc → bad substitution on bash 3.2; test masked it | patch — reason built outside heredoc; test asserts clean render |
| 7 | low | model could reset breaker state / STALLED message gave the command | patch — state writes blocked; message addressed to the human. `routing` left writable (known limitation) |
| 8 | low | background watchers blocked; out-of-repo new dir; `%b` escapes; unlocked ledger | patch ×3; ledger race deferred (fails open) |
