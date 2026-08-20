# Hydraia Loop-Hardening — design spec

**Date:** 2026-08-19
**Status:** approved design, ready for implementation plan
**Scope:** port five mechanisms from `cobusgreyling/loop-engineering` into hydraia as
runtime guarantees, to make the pipeline more precise, more autonomous, safer, and
cheaper in tokens — without regressing any existing Claude behavior, and staying
compatible with the in-flight Codex port.

## Goal

Add five loop-engineering primitives to hydraia:

1. **Circuit breaker** — a per-item attempt ledger with a hard hook block + escalation,
   mechanizing the soft caps that today live only as SKILL prose.
2. **Cost model + early-exit + token caps** — pre-flight estimate, cheap noop exit, and
   a hook-enforced daily/per-run token ceiling with a kill switch.
3. **Blast-radius path gate** — a `gate.yaml` denylist (secrets/auth/payments/…) +
   file-count guard enforced by a new dedicated hook.
4. **Binding constraints** — a per-repo `constraints.md` injected every session as
   binding context and read first in Phase 0.
5. **Autonomy tiers** — a Phase -1 size/risk classifier that maps to hydraia's existing
   controls (quick-mode, review depth) instead of adding a new axis.

**Design stance (matches hydraia's existing hooks):** every enforcement is a *runtime
guarantee*, not a prompt the model can rationalize past. All hooks **fail open** (any
internal error → allow), are **opt-in per repo** (only fire where hydraia is in use),
carry an **un-forgeable env-var human override** (never the model's call), and read
config via `hy_config`. All new *data* files are **agent-agnostic** so the Codex port
reads the same files without duplication.

## Non-goals (YAGNI)

- Loop patterns as cron (PR Babysitter / CI Sweeper / etc.) — that is item #6, a later
  phase that depends on all five hardening mechanisms landing first.
- Auto-merge (hydraia does not merge). `autoMergeAllowlist` ships as *data only* in
  `gate.yaml`, reserved for the future loop patterns; nothing consumes it now.
- A numeric "Loop Readiness Score" (loop-audit homolog) — deferred.
- Changing the Claude ↔ Codex contract split defined by the Codex port spec.

## Terminology

- **Artifacts base / `$hbase`** — the resolved dir where hydraia writes all state for a
  repo: `<repo>/docs/hydraia/` by default, or an external dir chosen at the storage
  gate. Resolved by `hy_artifacts_dir` in `hooks/config.sh`.
- **Opt-in** — a repo "uses hydraia" when the artifacts base exists, OR the repo is
  registered in the global config, OR a legacy `docs/hydraia/` dir exists. Every hook
  reuses this exact test (copied from `gate.sh` / `agents.sh`).
- **Active-plan window** — the period a frozen plan is armed: `$hbase/.active-plan`
  present and fresh (< 12h). Phase 3 arms it; Phase 6 disarms it.

---

## Feature 1 — Circuit breaker (ledger + hard hook)

### Problem

hydraia already bounds two failure loops, but only as SKILL prose:
- Phase 4: a hung executor is re-pushed up to `maxTaskRetries` (default 2), then
  declared a blocker.
- Phase 5: "re-review only … max one re-review cycle."

Prose is not a guarantee — a determined orchestrator can spin fix→review→fix and burn
50k–200k tokens per cycle. loop-engineering's contribution is a **mechanical** attempt
ledger with escalate-after-N.

### Mechanism

**Ledger file (shared data):** `$hbase/.agents/ledger.json` (the `.agents/` dir already
exists — `agents.sh` uses it for the per-run agent counters; the run-reset already
clears siblings). Schema:

```json
{
  "runId": "<active-plan mtime epoch>",
  "items": {
    "task:<slug>":   { "attempts": 2, "lastTs": 1755600000, "status": "retrying" },
    "review:<branch>": { "cycles": 1, "lastTs": 1755600100 }
  }
}
```

`runId` = the active-plan mtime (same value `agents.sh` already uses to detect a new
run). When it changes, the ledger is reset to `{}` alongside the existing counter reset.

**Task slug:** the orchestrator tags each executor dispatch prompt with a
machine-readable `[task:<slug>]` marker (SKILL Phase 4 updated to include it; `<slug>`
is the same task-slug the executor already uses for its heartbeat file
`$hbase/.heartbeats/<slug>`). The hook parses `[task:<slug>]` from the Task
`tool_input`; if absent, it falls back to a short hash of the task `description` so the
breaker still counts (never fails to a no-op silently — logs a degraded note).

**Enforcement (extends `hooks/agents.sh`):** `agents.sh` already runs on
`PreToolUse:Task` under a portable lock. Inside that same critical section:

1. Resolve the slug (or review-cycle key for reviewer agent types).
2. Read `ledger.json`; look up the item.
3. **For executor task-slugs:** if `attempts >= maxTaskRetries` → BLOCK (exit 2) with an
   escalation message (evidence: slug, attempts, whether a commit exists). Otherwise
   increment `attempts`, write the ledger, allow.
4. **For reviewer dispatches** (`hydraia-reviewer` / the reviewer agent types): key
   `review:<branch>`; if `cycles >= maxReviewCycles` (default 2) → BLOCK + escalate;
   else increment, allow.

Increment and total-agent counting happen under the one lock, so a same-turn burst is
serialized exactly like the existing cap. The block message tells the orchestrator to
**stop and surface the blocker to the human**, never to retry the blocked dispatch.

**SKILL changes:** Phase 4 and Phase 5 read `ledger.json` and escalate to the human with
the recorded evidence when the cap is hit, instead of looping. The env override
`HYDRAIA_ALLOW_DIRECT=1` lifts the breaker (same as it lifts the agent cap). The human
may raise `maxTaskRetries` / `maxReviewCycles` via env or config.

### Config

- Reuses `maxTaskRetries` (default 2, already exists) / `HYDRAIA_MAX_TASK_RETRIES`.
- New `maxReviewCycles` (default 2) / `HYDRAIA_MAX_REVIEW_CYCLES`.
- `HYDRAIA_ALLOW_DIRECT=1` lifts the breaker.

### Failure modes

- No slug and no description → degraded hash key; still counts, logs a note. Fail-open
  never means fail-silent for the breaker.
- Ledger unreadable/corrupt → treat as empty (allow), log a note; a corrupt ledger must
  never wedge a run.
- Reviewer/executor type detection wrong → conservative: only the known reviewer agent
  types get the review-cycle key; everything else is treated as an executor slug.

---

## Feature 2 — Cost model + early-exit + token caps

### Problem

The pipeline always runs full ceremony. A noop (empty diff review, nothing-to-fix perf
run) pays the same as real work. There is no pre-flight cost signal and no spend
ceiling; telemetry is recorded only *after* a run (`summary.sh`).

### Mechanism — three parts

**(a) Early-exit (noop guard) — SKILL Phase -1/0.** For routes whose target can be
empty:
- `review` / `graph`: if `git diff --name-only` against the branch point is empty (or
  the named target does not exist) → emit a one-line "nothing to review" report, drop
  the run-complete marker (brief), and exit. No Phase 0–6.
- `perf` / `db`: if the named symptom target is absent / already within a stated
  threshold → report and exit.
- `feature`: the noop path is the Tier-S quick-mode from Feature 5 (trivial change skips
  ceremony), not a separate mechanism.
This is prose in the orchestrator; it needs no hook (the orchestrator controls whether
it spins the phases).

**(b) Pre-flight cost estimate (shared data).** `patterns/cost.yaml`, adapted from
loop-engineering's `registry.yaml` cost block, keyed by route × tier:

```yaml
version: 1
routes:
  feature:
    S: { tokens_noop: 5000,  tokens_report: 40000,  tokens_action: 200000 }
    M: { tokens_noop: 5000,  tokens_report: 60000,  tokens_action: 600000 }
    L: { tokens_noop: 5000,  tokens_report: 80000,  tokens_action: 1500000 }
  review:  { any: { tokens_noop: 5000, tokens_action: 120000 } }
  perf:    { any: { tokens_noop: 5000, tokens_action: 300000 } }
defaults:
  suggested_daily_cap: 0        # 0 = off (opt-in)
```

Phase -1 reads it and prints a one-line estimate for the chosen route + tier. Pure data;
editable without code changes. Values are rough order-of-magnitude anchors, not
promises.

**(c) Token caps + kill switch (hook-enforced, extends `agents.sh`).** `summary.sh`
already appends one telemetry record per completed run to
`~/.cache/hydraia/telemetry.jsonl` (with `ts` and total `tokensIn`/`tokensOut`). At each
Task dispatch, inside the existing lock, `agents.sh`:

1. If `loopPause` config is true OR `HYDRAIA_PAUSE` env is set → BLOCK all dispatch with
   a "loop paused" message (kill switch; loop-engineering's `loop-pause-all` homolog).
2. If `dailyTokenCap > 0`: sum `tokensIn+tokensOut` from telemetry records with `ts`
   within the last 24h; if over cap → BLOCK new dispatch with a "daily budget reached —
   switch to report-only" message.
3. If `perRunTokenCap > 0`: same check scoped to the current `runId` window.

Caps default to `0` (off) — spend enforcement is opt-in, never a surprise. The estimate
(b) is always shown; the cap (c) only bites when configured. All three checks fail open
(telemetry unreadable → allow) so accounting never wedges a run.

**Doc:** `loop-budget.md` at repo root documents the caps, the kill switch, and the
`loop-cost` estimate flow for humans (loop-engineering's `loop-budget.md` homolog).

### Config

- `dailyTokenCap` (default 0 = off) / `HYDRAIA_DAILY_TOKEN_CAP`.
- `perRunTokenCap` (default 0 = off) / `HYDRAIA_RUN_TOKEN_CAP`.
- `loopPause` (default false) / `HYDRAIA_PAUSE` (env is the un-forgeable kill switch).

### Failure modes

- Telemetry file missing/short (fresh install, first run) → treated as 0 spend → allow.
  The cap protects a busy day, not a cold start.
- Clock skew on the 24h window → best-effort; the cap is a soft budget guard, not a
  billing system. `HYDRAIA_ALLOW_DIRECT` / raising the cap is the human's escape.
- Telemetry lag: `summary.sh` writes at run close, so a single very long run can exceed
  the cap before it is recorded. Accepted: the cap throttles run *count* per day, and
  `perRunTokenCap` is the within-run guard (still approximate). Documented, not solved to
  the token.

---

## Feature 3 — Blast-radius path gate (`blastgate.sh`)

### Problem

`gate.sh` enforces spec-before-code but does **not** stop an edit to `.env`, `auth/`,
`payments/`, `secrets/`, or a runaway 40-file diff. That is a real safety hole today,
including under prompt injection.

### Mechanism

**New hook `hooks/blastgate.sh`**, wired in `hooks.json` under `PreToolUse` for
`Edit|Write|MultiEdit` (a second command alongside `gate.sh`). Separate file from
`gate.sh` — spec-drive and blast-radius are distinct concerns; each stays focused and
independently testable (matches hydraia's one-purpose-per-hook structure).

**Data `gate.yaml`** at repo root (loop-engineering's exact format):

```yaml
version: 1
denylist:
  - ".env"
  - ".env.*"
  - "**/secrets/**"
  - "**/credentials/**"
  - "**/*_key*"
  - "**/*_secret*"
  - ".terraform/**"
  - "k8s/production/**"
  - "**/migrations/**"
  - "auth/**"
  - "payments/**"
  - "billing/**"
maxFiles: 10
autoMergeAllowlist:      # data only — reserved for future loop patterns; unused now
  - "docs/**"
  - "**/*.md"
```

hydraia ships `gate.yaml.sample`; if a repo has no `gate.yaml`, the hook uses a built-in
default denylist identical to the sample's `denylist`, so protection is on out of the
box. A repo `gate.yaml` overrides the built-in default.

**Logic:**
1. Parse target `file_path` from the payload (same python one-liner as `gate.sh`).
2. Opt-in test (identical to `gate.sh`). Not a hydraia repo → allow.
3. `HYDRAIA_ALLOW_DIRECT` set → allow (human bypass).
4. `pathGate` config: `off` → allow; `strict` (default) → enforce.
5. Normalize `file_path` to repo-relative; glob-match against the denylist. Match →
   BLOCK (exit 2) with a message naming the matched rule and the env bypass. The
   pipeline's own artifacts (`$hbase/**`, `*.md`) are exempt (same exemption as
   `gate.sh`) so hydraia can always write specs/plans.

**maxFiles (advisory by default):** during an active-plan window, count distinct
`file_path`s edited this run (a `$hbase/.agents/edited-files` set, reset per run like the
other counters). Past `maxFiles`, emit a **warning to stderr** but allow — a real
multi-file feature is legitimate. Set `maxFilesEnforce=true` to turn the warning into a
block (exit 2). Outside an active-plan window (ad-hoc / quick-mode edits) the count is a
stronger signal of a runaway edit; still advisory in v1, enforce opt-in.

### Config

- `pathGate` (default `strict`) / `HYDRAIA_PATH_GATE` (`off` disables).
- `maxFilesEnforce` (default false) / `HYDRAIA_MAX_FILES_ENFORCE`.
- `HYDRAIA_ALLOW_DIRECT=1` bypasses (human).

### Failure modes

- `gate.yaml` unparseable → fall back to the built-in default denylist, log a note.
- Glob engine differences (bash extglob vs python fnmatch) → the hook matches in python3
  (`fnmatch`/`PurePath.match`) for portability, mirroring how `gate.sh` parses in
  python3; if python3 is absent, fail open (allow) — same contract as every other hook.
- Path outside the repo (absolute temp path) → not repo-relative → allow (not a managed
  edit).

---

## Feature 4 — Binding constraints (SessionStart injection + Phase 0)

### Problem

hydraia has skills, but none is "read first and binding." Per-repo rules ("never touch
this module", "always run tests first", "don't push without telling me") are not carried
into every session — the agent starts cold (intent debt).

### Mechanism

**Data `docs/hydraia/constraints.md`** (per-repo, git-tracked; ship
`constraints.sample.md`). loop-engineering's binding format: Push/Merge, Paths, Code,
Communication, Budget sections. Lives under the in-repo artifacts path by default; in
external-artifacts mode it lives at `$hbase/constraints.md` (resolved via
`hy_artifacts_dir`), so both modes work.

**Injection (extends `hooks/preflight.sh`, SessionStart):** preflight already runs at
SessionStart. Add: if a constraints file exists and `constraintsInject` is true, read it
(cap length, e.g. 8 KB) and emit it as `additionalContext` via a JSON stdout payload:

```json
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<constraints text>"}}
```

so every session — pipeline or ad-hoc — carries the rules as binding context. (Today
preflight emits only stderr nudges; this adds the structured stdout channel. The existing
stderr nudges are preserved.)

**Phase 0 (SKILL):** the orchestrator reads `constraints.md` explicitly alongside config
and treats it as binding, so the rules are honored even if a session's additionalContext
was truncated.

**Appending:** v1 keeps it simple — the user edits the file, or asks the orchestrator to
append a rule (an Edit to a markdown file, which the gates already exempt). No new
command in v1 (loop-engineering's `/constraints` is a nice-to-have, deferred).

### Config

- `constraintsInject` (default true) / `HYDRAIA_CONSTRAINTS` (`off` disables injection).

### Failure modes

- No constraints file → inject nothing (silent). The feature is invisible until a repo
  opts in by creating the file.
- File too large → truncate to the cap with a trailing "(truncated — see
  constraints.md)" note; Phase 0's explicit read covers the full file.
- Malformed JSON emit → preflight must still exit 0 and never break SessionStart; the
  JSON is built by python3 and on any error we skip injection (stderr nudges still work).

---

## Feature 5 — Autonomy tiers (map to existing controls)

### Problem

One mode: full pipeline always. A typo triggers the same spec→plan→execute→double-review
ceremony as a feature. Overspend on trivial work.

### Mechanism (SKILL Phase -1, no new enforcement axis)

After route classification, Phase -1 estimates a **tier** from cheap signals — likely
files touched, overlap with the `gate.yaml` denylist (risk), new-logic vs mechanical
change, presence of UI surfaces:

- **Tier S (trivial):** no new logic, no new file, no risk-path, ≤ ~2 files → route to
  **quick-mode** (the existing `.quick-approved` human-approved path) or a Lite review.
  Minimal ceremony.
- **Tier M (standard):** default — full pipeline, Full review (today's behavior).
- **Tier L (large / risky):** many files, risk-path overlap, or new service → full
  pipeline + all gates + the human may raise the agent ceiling.

Phase -1 presents the tier **plus the cost estimate from Feature 2(b)** in a single
`AskUserQuestion`, pre-selecting the review depth (the Phase-3 run-controls picker) so
the human confirms with one tap and can override. This **reuses** quick-mode + the review
picker; it adds a classifier and a pre-selection, not a new control surface.

The tier is a *suggestion the human confirms*, never an autonomous downgrade of safety:
the security floor (Phase 5 mandatory reviewers, threat model) is **never** removed by a
tier — Tier S only trims optional ceremony, exactly like today's quick-mode already does.

### Config

- `autoTier` (default true) / `HYDRAIA_AUTO_TIER` (`off` → always Tier M, today's
  behavior).

### Failure modes

- Misclassification (S for something that is really M) → the human confirmation step is
  the backstop; the human sees the tier and the estimate and can bump it. The classifier
  never silently commits to a tier.
- Risk-path overlap detection reuses the `gate.yaml` denylist, so it stays in sync with
  Feature 3 automatically.

---

## Cross-cutting — Codex parity

The in-flight Codex port (see `2026-08-19-hydraia-codex-port-design.md`) requires **zero
changes to the Claude surface** with all Codex logic under `codex/`. This spec is
designed so the Codex session absorbs these five features cleanly:

**Shared data files (read by both agents, never duplicated):**
- `gate.yaml`
- `docs/hydraia/constraints.md` (or `$hbase/constraints.md`)
- `$hbase/.agents/ledger.json`
- `patterns/cost.yaml`
- `loop-budget.md`
- All new config keys (Codex reads the same `~/.config/hydraia/config.json` — its hooks
  source a Codex-flavored `config.sh` with the same `hy_config` contract).

**Duplicated logic the Codex session must add (separate files, same behavior):**
- `codex/hooks/blastgate.sh` — reads the same `gate.yaml`, Codex hook I/O schema.
- Breaker + token-cap logic in the Codex agents-budget hook — reads the same
  `ledger.json` and telemetry.
- Constraints injection in `codex/hooks/preflight.sh` — same file, Codex
  additionalContext mechanism.
- `codex/setup.sh` installs the new `blastgate.sh` into `~/.codex` and wires it in
  `~/.codex/hooks.json`.

**Shared PIPELINE CONTRACT (kept byte-identical, enforced by the port's CI drift check):**
the Phase -1 tier logic, Phase 0 constraints read, and Phase 4/5 ledger-escalation text
go into the delimited contract block that must match between `skills/hydraia/SKILL.md`
and `codex/skills/hydraia/SKILL.md`.

**Coordination note:** the `codex/` tree is owned by the parallel session and may not
exist on this branch yet. This spec's implementation delivers the **full Claude side +
all shared data files**, and the implementation plan produces a **"Codex Parity
Checklist"** artifact (`docs/hydraia/specs/loop-hardening-codex-parity.md`) enumerating
the exact files/mirrors above, so the Codex session picks it up without collision. This
implementation does **not** edit `codex/` files (avoids stepping on the parallel work);
if the `codex/` dir already exists, the checklist is dropped in as a to-do, not applied.

---

## Config summary (all via `hy_config`, dashboard-editable, env overrides)

| Key | Default | Env | Feature |
|-----|---------|-----|---------|
| `pathGate` | `strict` | `HYDRAIA_PATH_GATE` | 3 |
| `maxFilesEnforce` | `false` | `HYDRAIA_MAX_FILES_ENFORCE` | 3 |
| `constraintsInject` | `true` | `HYDRAIA_CONSTRAINTS` | 4 |
| `maxReviewCycles` | `2` | `HYDRAIA_MAX_REVIEW_CYCLES` | 1 |
| `dailyTokenCap` | `0` (off) | `HYDRAIA_DAILY_TOKEN_CAP` | 2 |
| `perRunTokenCap` | `0` (off) | `HYDRAIA_RUN_TOKEN_CAP` | 2 |
| `loopPause` | `false` | `HYDRAIA_PAUSE` | 2 |
| `autoTier` | `true` | `HYDRAIA_AUTO_TIER` | 5 |
| `maxTaskRetries` | `2` (exists) | `HYDRAIA_MAX_TASK_RETRIES` | 1 |
| `HYDRAIA_ALLOW_DIRECT` | unset | (env only) | 1,3 bypass |

## Files

**New:**
- `hooks/blastgate.sh`
- `gate.yaml` + `gate.yaml.sample`
- `docs/hydraia/constraints.sample.md`
- `patterns/cost.yaml`
- `loop-budget.md`
- `hooks/tests/` (shell hook tests — added if no harness exists)
- `docs/hydraia/specs/loop-hardening-codex-parity.md` (checklist artifact)

**Modified:**
- `hooks/hooks.json` — wire `blastgate.sh`
- `hooks/agents.sh` — breaker attempt counting + token caps + kill switch
- `hooks/preflight.sh` — constraints additionalContext injection
- `hooks/summary.sh` — optional cost line (spend vs cap) in the run summary
- `skills/hydraia/SKILL.md` — Phase -1 tier + cost + noop, Phase 0 constraints read,
  Phase 4/5 ledger escalation, `[task:<slug>]` dispatch tag
- `hooks/doctor.sh` — validate presence/shape of `gate.yaml` + surface new deps (light)
- `README.md` / `README.es.md` / `CHANGELOG.md`

**Unchanged (hard constraint):** no edits to `codex/` (owned by the parallel session);
the parity checklist artifact is the interface.

## Testing

Shell hook tests: feed each hook a crafted JSON payload on stdin and assert the exit code
+ message, matching how `agents.sh`'s logic is exercised (block=exit 2, allow=exit 0).
Cases per feature:
- **blastgate:** denylist hit blocks; non-denylist allows; `pathGate=off` allows;
  `HYDRAIA_ALLOW_DIRECT` allows; `$hbase`/`*.md` exempt; missing `gate.yaml` uses default.
- **breaker:** N-th executor dispatch past `maxTaskRetries` blocks; reviewer past
  `maxReviewCycles` blocks; ledger reset on new `runId`; corrupt ledger allows.
- **caps:** `loopPause`/`HYDRAIA_PAUSE` blocks; over `dailyTokenCap` blocks; caps `0`
  never block; missing telemetry allows.
- **constraints:** preflight emits valid additionalContext JSON when the file exists and
  `constraintsInject=true`; nothing when absent; still exit 0 on malformed input.
- **tiers:** classifier unit-checked at the SKILL/prose level (no hook); manual/e2e.

If `hooks/` has no test harness, add a minimal `hooks/tests/run.sh` that drives each hook
with fixtures and asserts exit codes; wire it into the repo's existing CI if present.

## Success criteria

1. An edit to `.env` / `auth/**` / `payments/**` is BLOCKED by `blastgate.sh` (with the
   env bypass working), out of the box with no `gate.yaml`.
2. The N+1-th retry of a failing task past `maxTaskRetries`, and the review cycle past
   `maxReviewCycles`, are BLOCKED with an escalation message — verified via ledger.
3. With `dailyTokenCap` set and exceeded, new Task dispatches are blocked; `HYDRAIA_PAUSE`
   blocks all dispatch immediately; caps at `0` never interfere.
4. A repo `constraints.md` appears as binding context at SessionStart and is read in
   Phase 0.
5. Phase -1 prints a tier + cost estimate and pre-selects review depth; the human
   confirms/overrides; the security floor is never removed by a tier.
6. Zero edits to `codex/`; the parity checklist artifact fully enumerates the Codex-side
   mirror work.
7. All hooks fail open on malformed input and stay opt-in (non-hydraia repos untouched);
   existing hydraia runs are not regressed.
