---
description: Run only Hydraia analysis + spec + detailed plan (with self-review loop), then stop
argument-hint: <what you want to plan>
---

Invoke the **hydraia** skill but run ONLY Phases 0-3: context (code graph + PDF conversion if needed), think-before-coding gate, design + threat model, and the detailed implementation plan with its self-review loop (max 2 iterations). Then STOP — do not execute.

Produce BOTH artifacts: the written design spec under docs/hydraia/specs/ (goal, chosen vs rejected approaches, code-graph anchors, global constraints, threat model) and the frozen, file-level-detailed plan under docs/hydraia/plans/. Do NOT arm the spec-drive gate and do NOT write feature code — this is the human review point before implementation.

Request: $ARGUMENTS
