---
description: Sync README, API docs, CHANGELOG, and the ADR index with the actual code — reports drift, never invents behavior
argument-hint: <optional focus — e.g. "the API reference">
---

Dispatch the **docs-engineer** agent (mode: full). Sync the README (features, command tables, counts, version badge), API contract docs (OpenAPI/GraphQL if present), CHANGELOG (Keep-a-Changelog), and the ADR index against the real code surface. Document only what exists — gaps are reported, never filled with guesses. Report files updated and drift found (fixed vs still-open).

Focus: $ARGUMENTS
