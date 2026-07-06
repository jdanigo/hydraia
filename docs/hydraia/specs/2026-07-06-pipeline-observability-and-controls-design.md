# Design — Pipeline observability & run controls (v0.10.0)

**Date:** 2026-07-06
**Status:** approved (user answered the three design questions; recommendations accepted)

## Goal

Close five gaps surfaced by a real production run of the Hydraia pipeline:

1. **Telemetry is incomplete.** Dashboard showed `0` agents dispatched and only the
   Opus model, even though the run fanned out several Sonnet 5 sub-agents that each
   spent tokens. Sub-agent usage was never attributed.
2. **Review depth is not selectable per run.** The full double-review ceremony runs
   even for a trivial change, burning tokens the human might not want to spend.
3. **Hung sub-agents are undetected.** Several executors stalled and had to be pushed
   manually with a new message.
4. **Functional QA was done inline** by the main agent instead of producing a
   committed, reviewable test-case document.
5. **No closing run summary by default**, and no choice of brief vs detailed.

## Chosen approaches (rejected alternatives noted)

### 1. Full telemetry — sidecar for sub-agents, transcript sweep for main

**Root cause.** `hooks/summary.sh` parsed a single transcript file (the main session)
and aggregated every `message.usage`. Sub-agent (`Task`) turns run as `isSidechain`
entries and, across a compaction, land under a *different* session id / file — so the
Stop hook's transcript missed them entirely, yielding `agents=0` and Opus-only totals.

**Approach (chosen).** Two sources, merged, deduped by entry `uuid`:
- **Main session:** `summary.sh` reads the transcript's `sessionId` and sweeps every
  `*.jsonl` in the project dir for entries with that id and `isSidechain=false` →
  main-session model/token totals; `Task`/`Skill` `tool_use` blocks → agent-by-type
  and skill counts.
- **Sub-agents:** `hooks/agents.sh` already fires on `SubagentStop`. Extend it to
  delta-capture the finishing sub-agent's `isSidechain` assistant-turn usage (model,
  in/out/cache) into a **repo-scoped sidecar** `docs/hydraia/.agents/subagents.jsonl`,
  deduped by a persisted seen-uuid set, reset per run (keyed to the active-plan
  `runid` already tracked). Because it lives in the repo and accumulates as agents
  finish, it survives compaction and session changes — the exact failure mode above.
- **Total agent count** = `max(sidecar line count, main-transcript Task-block count)`.

**Rejected:** (a) parse only the Stop-hook transcript harder — cannot recover turns
that are not in that file; (b) a `SubagentStop` sum of the *whole* transcript — double
counts without uuid dedup; (c) global `~/.cache` sidecar — not run-scoped, races across
concurrent repos.

**Telemetry record (enriched, appended by `summary.sh` to
`~/.cache/hydraia/telemetry.jsonl`):** existing keys plus
`main:{tokensIn,tokensOut,models}`, `subagents:{count,tokensIn,tokensOut,cacheRead,
models,byType}`. `models` stays the combined main+sub map for dashboard back-compat.

**Dashboard (`server.js` + `index.html`):** aggregate and render the new fields — real
agent count, **per-model IN *and* OUT** (was input-only), a sub-agent usage panel
(count, tokens, models), and a per-run drill-down in the Recent-runs table.

### 2. Review-depth picker — Full / Lite / Custom at plan freeze

At the end of Phase 3 (plan frozen, before the autonomous half begins so 4–6 stay
pause-free) the pipeline asks **once** via `AskUserQuestion`:
- **Full** — current behavior: double review, all matched language reviewers, security
  gates, QA, E2E, docs sync.
- **Lite** — single review pass, skip non-core language reviewers and docs-sync; **the
  security floor still runs** (see below); QA/E2E per repo surface.
- **Custom** — a second multi-select over the *optional* stages: 2nd review pass,
  language/framework reviewers, type-design/perf reviewers, docs sync, extra OWASP
  pass.

**Security floor (never optional in any profile):** `security-scan`, `code-reviewer`,
`silent-failure-hunter`, `security-reviewer`, and one `hydraia-reviewer` pass always
run. The picker cannot remove them — matches the pipeline's existing "security is not
skippable" stance. The human can still hard-disable via `securityGates=false` config,
which is a separate, explicit act.

The choice is honored in Phases 5–6 and recorded in the run log. **Rejected:** always
showing the granular checklist (one extra decision every run); config-only (does not
meet the "ask me each run" request).

### 3. Watchdog — heartbeat + auto re-push at wave boundaries

Claude Code's `Task` dispatch **blocks** the main loop; there is no in-harness timer to
wake "every X minutes" mid-wave. Honest mechanism:
- Executors (`hydraia-executor`, `qa-automation`) write a heartbeat on start and after
  each commit: `docs/hydraia/.heartbeats/<task-slug>` (epoch seconds). `.heartbeats/`
  is gitignored.
- Phase 4 already dispatches in bounded waves (`HYDRAIA_MAX_CONCURRENT`, default 6) and
  verifies commits after each wave. Strengthen the wave-return check: any task in the
  returned wave with **no commit** and a **stale/absent heartbeat** (older than
  `heartbeatStaleSecs`, default 300) is treated as stalled and **auto re-dispatched**
  ("pushed") — up to `maxTaskRetries` (default 2). Retries are logged in the run log;
  after they are exhausted the pipeline surfaces a genuine blocker instead of spinning.
- Executors are instructed to be time-boxed: commit or report `BLOCKED` explicitly,
  never spin — a spinning agent is the root cause of the manual-push pain.

**Rejected:** a detached background daemon polling transcript mtimes — fights the
harness (the main agent is blocked during a `Task` anyway), OS-dependent, more moving
parts, and a plugin should not spawn daemons.

### 4. QA cases always a committed document

- Phase 3: the main agent **must** dispatch `qa-functional` to produce
  `docs/hydraia/qa/YYYY-MM-DD-<slug>-cases.md` and **the pipeline commits it**. The main
  agent is **forbidden** from performing functional QA inline. When a run has no formal
  acceptance criteria, `qa-functional` derives implicit ACs from the spec so a case doc
  is still produced.
- The frozen-plan condition gains: the QA-case doc exists and is committed. Phase 6's
  existing matrix check is unchanged.
- `docs/hydraia/qa/` becomes a tracked directory (`.gitkeep`).

### 5. Closing summary — brief vs detailed, asked at plan freeze

- The summary is emitted by the `Stop` hook, which cannot prompt. So the **choice** is
  taken at plan freeze (batched with the review-depth question, keeping 4–6 pause-free)
  and written into the one-shot marker: `printf 'detailed\n' > docs/hydraia/.run-complete`
  (or `brief`). `summary.sh` reads the marker's first line to pick verbosity.
- **Brief** = the current compact box (models, agents, tokens, skills).
- **Detailed** = adds what shipped (from the run log + `git diff --stat`), per-agent-type
  counts, main-vs-sub-agent token split, per-model in/out/cache, and skills with counts.

## Config keys added

`heartbeatStaleSecs` (300), `maxTaskRetries` (2). Surfaced in the dashboard config form
and documented in `hooks/config.sh` consumers list. `reviewMode`/`runSummary` etc.
already exist; the new picker sets per-run overrides in-session, it does not replace the
config file.

## Blast radius (files)

`hooks/summary.sh`, `hooks/agents.sh`, `.gitignore`, `docs/hydraia/qa/.gitkeep`,
`dashboard/server.js`, `dashboard/index.html`, `skills/hydraia/SKILL.md`,
`agents/hydraia-executor.md`, `agents/qa-automation.md`, `agents/qa-functional.md`,
`commands/feature.md` (note), `.claude-plugin/plugin.json`, `CHANGELOG.md`,
`README.md`, `README.es.md`.

## Threat model

All changes are local-only. Telemetry never leaves the machine (dashboard binds
127.0.0.1). The sidecar and heartbeats hold no secrets — only token counts, model
names, and epoch timestamps. QA docs are committed to the repo the user already
controls. No new untrusted input, network call, or auth surface. Shell hooks continue
to fail-open (never wedge a run) and parse untrusted transcript JSON defensively in
`python3`, matching existing patterns.
