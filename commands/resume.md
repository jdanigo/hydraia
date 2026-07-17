---
description: Resume an interrupted Hydraia pipeline from the last incomplete phase
argument-hint: [optional run-log name; defaults to the most recent]
---

Invoke the **hydraia** skill in resume mode.

0. Resolve the artifacts base first (in-repo `docs/hydraia/` or the external dir the user chose at the storage gate) and inherit that run's **storage location** and **auto-commit** choice from the run log if recorded; if neither is recorded, re-run the Storage & commit gate. Every `docs/hydraia/...` path below is relative to the resolved base.
1. Find the run log: if $ARGUMENTS names one, use `<artifacts base>/runs/$ARGUMENTS`; otherwise use the most recently modified file in `<artifacts base>/runs/`.
2. Read it to recover the original request, the linked plan under `docs/hydraia/plans/`, and the phase checklist. Do NOT re-plan — reuse the frozen plan and spec.
3. Continue the pipeline from the FIRST unchecked phase, obeying the continuous-execution rule (do not stop until the plan is complete or a genuine blocker appears).
4. Update the run log's checkboxes as phases complete.
5. On completion, print the credits line, exactly:
   `— Harness By José Daniel Garcés Ospina | Spec Drive Design First —`
