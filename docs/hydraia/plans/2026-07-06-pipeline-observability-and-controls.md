# Plan — Pipeline observability & run controls (v0.10.0)

**Goal:** Implement the five changes in
`docs/hydraia/specs/2026-07-06-pipeline-observability-and-controls-design.md`:
full sub-agent telemetry, per-run review-depth picker, hung-agent watchdog
(heartbeat + auto re-push), always-committed QA case doc, and brief/detailed
closing summary.

**Architecture:** Hooks (`agents.sh` SubagentStop sidecar, `summary.sh` merged
aggregation), dashboard (`server.js`/`index.html`) render, and pipeline prose
(`skills/hydraia/SKILL.md`, executor/QA agents). Local-only; no network surface.

**Tech stack:** Bash + embedded python3 (hooks), Node built-ins (dashboard),
Markdown (skill/agents/docs).

**Spec:** `docs/hydraia/specs/2026-07-06-pipeline-observability-and-controls-design.md`

## Global constraints
- Hooks fail-open (exit 0 on any error); parse untrusted transcript JSON in python3.
- No `Co-Authored-By: Claude` trailer on hydraia commits.
- Telemetry stays local (dashboard binds 127.0.0.1).
- Security floor never removable by the review picker.
- Release version: 0.10.0. No Claude commit trailer.

## Tasks
1. **agents.sh SubagentStop sidecar** — delta-capture sub-agent usage to
   `docs/hydraia/.agents/subagents.jsonl`, dedup by uuid, reset per runid.
2. **summary.sh merged aggregation + brief/detailed** — main tokens from transcript
   sweep by sessionId; sub-agent tokens/count from sidecar; enriched telemetry
   record; marker-driven verbosity.
3. **dashboard server.js** — aggregate new telemetry fields (per-model in/out,
   sub-agent split, real agent count).
4. **dashboard index.html** — render agent count, per-model IN+OUT, sub-agent panel,
   recent-run drill-down; add `heartbeatStaleSecs`/`maxTaskRetries` config fields.
5. **SKILL.md** — Phase 3 review+summary picker & QA-doc mandate; Phase 4 watchdog
   re-push; Phase 5 honor review profile; Phase 6 summary marker content.
6. **executor + QA agents** — heartbeat markers; qa-functional committed doc.
7. **Docs + release** — plugin.json 0.10.0, CHANGELOG, README EN/ES, commit, tag.

Each task self-verifies: `bash -n` on hooks, `node --check` on dashboard, grep for
inserted anchors, dashboard preview smoke test.
