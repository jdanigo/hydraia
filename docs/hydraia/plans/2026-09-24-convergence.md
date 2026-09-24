# Plan — Convergence (v0.22.0)

Design decisions, the I/O matrix and payload facts are copied into each task below so every
task stands on its own. Exec class noted per task. Branch: `feature/convergence`.

---

## Task 1 — Shared failure signature + baseline helper  (Exec: logic)

**Files:** Create `hooks/lib/failsig.py`, `hooks/baseline.sh`, `hooks/tests/test-baseline.sh`.

Contract:
- `failsig.py` CLI: `python3 failsig.py lines < text` prints the normalized failure lines
  (sorted, unique); `python3 failsig.py sig < text` prints a 12-hex sha1 signature.
  Normalize: strip ANSI escapes, durations (`12ms`, `1.5 s`), ISO/clock timestamps, hex
  addresses (`0x…`), temp paths (`/tmp/…`, `/var/folders/…`, `/private/…`), collapse
  whitespace. Failure line = matches `fail|error|✗|✕|×|panic|traceback|assert|exception|
  expected` (case-insensitive) but NOT the harness wrapper `^Error: Exit code \d+$`.
  No failure lines → last 15 non-empty normalized lines. Read at most the last 200 KB.
- `baseline.sh -- <cmd…>`: resolve artifacts base via `config.sh` `hy_artifacts_dir`
  (fallback `<repo>/docs/hydraia`); run the command through python `subprocess` with
  timeout `HYDRAIA_BASELINE_TIMEOUT` (default 600 s); write normalized failure lines to
  `<base>/.baseline-failures` (first line `# head=<git sha> ts=<epoch>`); print exactly one
  of `BASELINE: CLEAN`, `BASELINE: <N> pre-existing failure line(s)` (+ up to 20 lines),
  `BASELINE: TIMEOUT after <s>s` (+ tail). Exit 0 (informational); exit 64 on usage error.

**Verify:** `bash hooks/tests/run.sh` → `test-baseline.sh` passes (clean command → CLEAN,
failing command → pre-existing count, `sleep` over timeout → TIMEOUT, file written).

## Task 2 — verifyloop.sh (no-progress ledger + background guard)  (Exec: logic)

**Files:** Create `hooks/verifyloop.sh`, `hooks/tests/test-verifyloop.sh`; Modify
`hooks/hooks.json`.

Contract:
- Events: PreToolUse(Bash), PostToolUse(Bash), PostToolUseFailure(Bash). Opt-in repo
  resolution identical to `agents.sh`. `HYDRAIA_ALLOW_DIRECT` → exit 0. Fail open.
- Verify command: default regex from spec D1; override `verifyPattern` /
  `HYDRAIA_VERIFY_PATTERN`.
- PreToolUse: (a) verify cmd + `tool_input.run_in_background == true` + no
  `timeout `/`gtimeout ` in cmd → exit 2 "background verify without timeout". Applies
  whenever opted in. (b) active fresh plan + ledger `stalled` set + verify cmd → exit 2
  STALLED.
- Failure detection: event `PostToolUseFailure`; or `tool_response` is a string starting
  `Error`; or dict with `exit_code`/`exitCode`/`returncode` ≠ 0. Text = `error` field or
  `tool_response` string or stdout+stderr.
- Only with a fresh `.active-plan` (<12 h): ledger `<base>/.agents/verify.json`
  `{runId, sigs:{sig:n}, stalled}`; runId = plan mtime, reset when it changes.
  Pre-existing (all failure lines ⊆ `<base>/.baseline-failures`, file <12 h) → exit 2
  note "pre-existing — do not fix", not counted. Else n+=1; n==2 → exit 2 NO PROGRESS;
  n ≥ `maxSameFailure` (default 3, env `HYDRAIA_MAX_SAME_FAILURE`) → set stalled, exit 2
  STALLED. Else exit 0.
- hooks.json: add verifyloop to the Bash PreToolUse list; add `PostToolUse` and
  `PostToolUseFailure` entries with matcher `Bash`.

**Verify:** `bash hooks/tests/run.sh` → `test-verifyloop.sh` passes all spec matrix rows
for verify/background/pre-existing/bypass; `python3 -m json.tool hooks/hooks.json`.

## Task 3 — agents.sh: fix budget + Opus gate  (Exec: logic)

**Files:** Modify `hooks/agents.sh`, `hooks/tests/test-breaker.sh`; Create
`hooks/tests/test-opusgate.sh`.

Contract:
- Role `fix` when description contains `[fix:<slug>]` (checked before sub_type):
  per-slug cap `maxFixAttempts` (2, `HYDRAIA_MAX_FIX_ATTEMPTS`) AND run cap
  `maxFixDispatches` (6, `HYDRAIA_MAX_FIX_DISPATCHES`); both counted only on allow.
- Opus gate (`opusGate` strict|warn|off, env `HYDRAIA_OPUS_GATE`; bypass
  `HYDRAIA_ALLOW_OPUS=1`), evaluated before caps, independent of `.active-plan`:
  judges = `hydraia-reviewer`, `security-reviewer`; generic unpinned = `general-purpose`,
  `Explore`, `Plan`, `claude`, empty. Effective Opus = `tool_input.model` contains
  `opus`, or (no model and type is generic unpinned). Judge → allow. Executor-class
  (`hydraia-executor`, `qa-automation`) with Opus allowed iff `<base>/.agents/routing`
  first line = `max-quality`. Otherwise strict → exit 2, warn → stderr note.
- Opus gate applies in opted-in repos only.

**Verify:** `bash hooks/tests/run.sh` → breaker fix-role cases + all opus-gate matrix rows.

## Task 4 — blastgate plan-scope gate  (Exec: logic)

**Files:** Modify `hooks/blastgate.sh`; Create `hooks/tests/test-scopegate.sh`.

Contract: after the denylist, before maxFiles, when `.active-plan` is fresh and names an
existing plan (relative to repo or absolute): collect backticked tokens (no spaces,
containing `/` or `.`, strip `:line`) from each `**Files:**` region (the line and its
non-blank continuation lines until a blank line or another `**Field:**`). Empty set →
skip. Allow: exact match, declared entry ending `/` as prefix, fnmatch glob, lockfiles
(`package-lock.json pnpm-lock.yaml yarn.lock bun.lockb go.sum Cargo.lock poetry.lock
uv.lock Gemfile.lock composer.lock`). Mode `scopeGate` (strict default, warn, off; env
`HYDRAIA_SCOPE_GATE`): strict → exit 2 with NEEDS_DECISION guidance; warn → note.

**Verify:** `bash hooks/tests/run.sh` → in-scope allowed, out-of-scope blocked, dir
prefix + glob allowed, legacy plan without Files → allowed, warn mode → exit 0.

## Task 5 — plancheck: `## Task` headings + contract rule  (Exec: logic)

**Files:** Modify `hooks/plancheck.sh`; Create `hooks/tests/test-plancheck.sh`.

Contract: task heading regex `^#{2,3} +Task` everywhere (was `^### +Task` — bug: level-2
plans were never scanned). New rule: every task block must contain a `**Files:**` line
and a line matching `Verify` (`**Verify:**`, `Verify:`, `- [ ] Verify`) → else BLOCK
listing the task titles. `planContract=off` (env `HYDRAIA_PLAN_CONTRACT`) disables it.

**Verify:** `bash hooks/tests/run.sh` → contract-complete plan allowed; missing Verify
blocked; `##` heading smell now caught.

## Task 6 — Agent model pins + executor/reviewer prose  (Exec: mechanical)

**Files:** Modify `agents/*.md` (frontmatter `model:` only, plus the two bodies below),
`agents/hydraia-executor.md`, `agents/hydraia-reviewer.md`.

Contract: `model: opus` stays only on `hydraia-reviewer`, `security-reviewer`; all
others → `model: sonnet`. Executor: reads its task from the plan path it is given;
stop-and-replan → `NEEDS_DECISION` (D8); fixes run only covering tests; never touches
files outside the task's Files. Reviewer: evidence rules + compact finding format.

**Verify:** `grep -l '^model: opus' agents/*.md` → exactly the two judges.

## Task 7 — Phase prose (levels, triage, bounded verify, thin orchestrator)  (Exec: logic)

**Files:** Modify `skills/hydraia/SKILL.md`, `skills/hydraia/phases/{phase--1-triage,
guards,model-policy,phase-0-context,phase-2-design,phase-3-plan,phase-4-execute,
phase-5-review,phase-6-verify}.md`; mirror every phase file to
`codex/skills/hydraia/phases/` and SKILL.md to `codex/skills/hydraia/SKILL.md` where the
Claude-specific parts allow.

Contract: implement spec D3, D4, D5, D6, D7, D9, D10, D12 in prose; replace "Opus 4.8"
with generation-agnostic wording; Phase-3 Pass B conditional; Phase-3 writes
`<base>/.agents/routing`; Phase-3 offers fresh-session continuation.

**Verify:** `diff -r skills/hydraia/phases codex/skills/hydraia/phases` empty;
`grep -rn "Opus 4.8" skills/hydraia` empty.

## Task 8 — Config, docs, release metadata  (Exec: mechanical)

**Files:** Modify `skills/hydraia/customize.toml`, `loop-budget.md`, `hooks/doctor.sh`,
`commands/review.md`, `README.md`, `README.es.md`, `CHANGELOG.md`,
`.claude-plugin/plugin.json`.

Contract: document new keys (`maxSameFailure`, `maxFixAttempts`, `maxFixDispatches`,
`verifyPattern`, `scopeGate`, `planContract`, `opusGate`, `[pipeline].level`); doctor
lists `verifyloop.sh`, `baseline.sh`; version 0.22.0; CHANGELOG entry.

**Verify:** `bash hooks/tests/run.sh` all green; `bash -n hooks/*.sh`;
`python3 -m json.tool .claude-plugin/plugin.json`.
