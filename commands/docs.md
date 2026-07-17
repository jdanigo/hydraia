---
description: Sync README, API docs, CHANGELOG, and the ADR index with the actual code — reports drift, never invents behavior
argument-hint: <optional focus — e.g. "the API reference">
---

Dispatch the **docs-engineer** agent (mode: full). Sync the README (features, command tables, counts, version badge), API contract docs (OpenAPI/GraphQL if present), CHANGELOG (Keep-a-Changelog), and the ADR index against the real code surface. Document only what exists — gaps are reported, never filled with guesses. Report files updated and drift found (fixed vs still-open).

Focus: $ARGUMENTS

When finished, record telemetry for this run: `printf 'brief\n' > <base>/.run-complete` (where `<base>` is the artifacts dir resolved at the storage gate — `docs/hydraia/` by default, or the external dir if chosen). The Stop hook logs this run's real token/model/sub-agent usage to the local dashboard (delta-scoped per session, so it never double-counts). Do not hand-write the numbers.
