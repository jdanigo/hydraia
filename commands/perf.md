---
description: Diagnose and fix a performance problem measurement-first — baseline, profile, numeric target, implement, re-measure
argument-hint: <symptom — e.g. "checkout endpoint p95 went from 200ms to 900ms">
---

Invoke the **hydraia** skill forcing the Phase -1 route to **performance**. Follow the performance-tuning skill: express the symptom as a metric, establish a measured baseline BEFORE any analysis (if measurement is impossible, deliver the measurement plan and stop), dispatch the perf-engineer agent for profile-driven diagnosis (and db-performance-tuner when findings are DB-shaped), write the spec with baseline + numeric target + chosen and rejected hypotheses, then run the full pipeline: plan, execute one isolated change per task, double review, and verify by RE-MEASURING with the baseline commands against the target.

Request: $ARGUMENTS
