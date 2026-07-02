---
description: Run only Hydraia analysis + spec + detailed plan (with self-review loop), then stop
argument-hint: <what you want to plan>
---

Invoke the **hydraia** skill but run ONLY Phases 0-3: context (code graph + PDF conversion if needed), think-before-coding gate, design + threat model, and the detailed implementation plan with its self-review loop (max 2 iterations). Then STOP — do not execute.

Output the frozen plan saved under docs/hydraia/plans/. Do not write feature code.

Request: $ARGUMENTS
