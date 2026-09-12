---
description: Explain a codebase, subsystem, or PR to a human — visually and verifiably. Grounds a diagram in codegraph's real structure and delivers a self-contained interactive HTML map with guided walkthrough chapters.
argument-hint: <what to explain — a subsystem, path, PR, or "how does X work">
---

Invoke the **explainme** skill to produce a visual, verifiable explanation of the code in
question. Follow the skill's Hydraia grounding first:

1. Resolve the scope from `$ARGUMENTS` (a subsystem, a path, a PR diff, or a "how does X
   work" question). Default to the current repo's headline subsystem if unscoped.
2. **Query codegraph** for the real structure — components/modules, call edges, entry
   points, storage/transports, blast radius. This is the topology source; do not guess it.
3. Pick the diagram type that fits (architecture / workflow / sequence / dataflow /
   lifecycle) — `node skills/explainme/bin/archify.mjs guide "<scenario>" --json` if unsure.
4. Author the typed IR from the verified codegraph nodes/edges; set `SRC` source-evidence
   from real file:line so nodes are click-through. Attach up to ~5 guided-walkthrough
   `views` chapters framing the onboarding path (request path / auth flow / data lineage /
   lifecycle).
5. Validate then deliver, running the CLI from the skill directory:
   `cd skills/explainme && node bin/archify.mjs validate <type> <in.json> --quality showcase --json`
   then `node bin/archify.mjs deliver <type> <in.json> <out.html> --json`. Consume the
   `diagnostics[]` repair receipts in a bounded loop (change only the diagnosed subject,
   at most one geometry control per repair, stop after two non-improving rounds).
6. Write the artifact under the resolved artifacts base (`<base>/explain/<slug>.html`) and
   hand the user the path. Do NOT run the full build pipeline — this is an explanation
   artifact, not a code change; no spec/plan/review gates apply.

Delegate the authoring to the `explainme` agent (Sonnet) when available; the deterministic
CLI carries the correctness. Requires Node ≥ 18 (see `/hydraia:doctor`).

Request: $ARGUMENTS
