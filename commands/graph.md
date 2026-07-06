---
description: Query the code graph for structure, call sites, and blast radius
argument-hint: <symbol, file, or question>
---

Query codegraph to answer the following about the current codebase. Prefer graph queries over broad file reads. Report call sites, dependencies, and blast radius concisely.

Query: $ARGUMENTS

When finished, record telemetry for this run: `printf 'brief\n' > docs/hydraia/.run-complete`. The Stop hook logs this run's real token/model/sub-agent usage to the local dashboard (delta-scoped per session, so it never double-counts). Do not hand-write the numbers.
