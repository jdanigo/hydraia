---
description: Run only Hydraia analysis + spec + detailed plan (with self-review loop), then stop
argument-hint: <what you want to plan>
---

Invoke the **hydraia** skill but run ONLY Phases 0-3: context (code graph + PDF conversion if needed), think-before-coding gate, design + threat model, and the detailed implementation plan with its self-review loop (max 2 iterations). Then STOP — do not execute.

Produce BOTH artifacts: the written design spec under docs/hydraia/specs/ (goal, chosen vs rejected approaches, code-graph anchors, global constraints, threat model) and the frozen, file-level-detailed plan under docs/hydraia/plans/ (both relative to the resolved artifacts base — the external dir when chosen at the storage gate). Do NOT arm the spec-drive gate and do NOT write feature code — this is the human review point before implementation.

Request: $ARGUMENTS

When finished, record telemetry for this run: `printf 'brief\n' > <base>/.run-complete` (where `<base>` is the artifacts dir resolved at the storage gate — `docs/hydraia/` by default, or the external dir if chosen). The Stop hook logs this run's real token/model/sub-agent usage to the local dashboard (delta-scoped per session, so it never double-counts). Do not hand-write the numbers.
