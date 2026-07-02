---
description: Resume an interrupted Hydraia pipeline from the last incomplete phase
argument-hint: [optional run-log name; defaults to the most recent]
---

Invoke the **hydraia** skill in resume mode.

1. Find the run log: if $ARGUMENTS names one, use `docs/hydraia/runs/$ARGUMENTS`; otherwise use the most recently modified file in `docs/hydraia/runs/`.
2. Read it to recover the original request, the linked plan under `docs/hydraia/plans/`, and the phase checklist. Do NOT re-plan — reuse the frozen plan and spec.
3. Continue the pipeline from the FIRST unchecked phase, obeying the continuous-execution rule (do not stop until the plan is complete or a genuine blocker appears).
4. Update the run log's checkboxes as phases complete.
5. On completion, print the credits line, exactly:
   `— Harness By José Daniel Garcés Ospina | Spec Drive Design First —`
