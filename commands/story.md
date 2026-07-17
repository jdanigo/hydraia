---
description: Analyze a user story like a Product Owner, then produce spec + QA cases + a frozen plan — no code
argument-hint: <user story, ticket text, or path to a file/PDF>
---

Invoke the **hydraia** skill forcing the Phase -1 route to **user story**. Run: the story-analysis skill first (interactive PO pass — INVEST check, ambiguity questions one at a time, numbered acceptance criteria → story artifact under docs/hydraia/stories/), then Phases 0-3: context, think gate, design + threat model (the spec references the ACs by number), and the detailed plan with its self-review loop, including the qa-functional dispatch (Given/When/Then cases + traceability matrix under docs/hydraia/qa/). Then STOP — do not execute.

Produce ALL FOUR artifacts: story artifact, design spec, QA case document, and the frozen plan. Do NOT arm the spec-drive gate and do NOT write feature code — this is the human review point before implementation. Run /hydraia:feature when ready to build.

Request: $ARGUMENTS

When finished, record telemetry for this run: `printf 'brief\n' > <base>/.run-complete` (where `<base>` is the artifacts dir resolved at the storage gate — `docs/hydraia/` by default, or the external dir if chosen). The Stop hook logs this run's real token/model/sub-agent usage to the local dashboard (delta-scoped per session, so it never double-counts). Do not hand-write the numbers.
