---
name: performance-tuning
description: Use when the request is a performance symptom — slow endpoint, high latency, timeouts, high CPU or memory, big bundle, slow build. Measurement-first methodology for the Hydraia perf route: baseline before analysis, numeric target in the spec, re-measure in verify. Never optimize without measuring.
---

# Performance Tuning — measure first, always

The performance route through the Hydraia pipeline. The pipeline phases are unchanged; this skill defines the two contract adaptations and the hard rules.

<HARD-RULES>
- NO optimization without a measured baseline. If there is no number, the first deliverable is the measurement, not the fix.
- The Phase 2 spec MUST contain: the baseline (metric, command, environment, runs, spread) and a NUMERIC target. A perf spec without numbers is not a spec.
- One variable at a time: each plan task isolates one change so Phase 6 re-measurement can attribute the gain.
- Phase 6 verify RE-MEASURES with the same commands as the baseline and compares against the target. Target missed → the run is NOT done: one more hypothesis cycle (max one), or an honest shortfall report. Never redefine the target post-hoc.
- Rejected hypotheses stay in the spec — what you chose NOT to optimize and why is part of the record.
</HARD-RULES>

## Route flow

1. **Symptom → metric.** Express the complaint as a measurable number (p50/p95 latency, throughput, CPU %, RSS, bundle KB, query ms).
2. **Baseline.** Run the measurement on representative data (state dev-vs-prod caveats). No access → the human runs the command you provide; the pipeline waits (interactive half).
3. **Diagnose.** Dispatch `perf-engineer` with the symptom + baseline. DB-shaped findings → it delegates to `db-performance-tuner` (dispatch that too). Their reports feed Phase 2.
4. **Spec.** Baseline + target + ranked hypotheses (chosen AND rejected) + threat model as usual. Then plan, freeze, gate — the normal pipeline from here.
5. **Execute.** Sonnet executors implement; one isolated change per task.
6. **Verify.** Re-run the exact baseline commands. Compare. Report measured before/after per change. Close only at/beyond target, or after the one allowed iteration with the shortfall stated plainly.

## Measurement pointers (per stack — pointers, not tutorials)

- **Node:** `node --cpu-prof`, `clinic flame`, `0x`; web: Chrome DevTools tracing, Lighthouse, Web Vitals.
- **Python:** `cProfile` + `snakeviz`, `py-spy record` (live processes).
- **Go:** `go test -bench`, `pprof` (CPU/heap), `trace`.
- **JVM:** `async-profiler`, JFR.
- **CLI/anything:** `hyperfine` for wall-clock A/B.
- **DB:** see the db-optimization skill.

Report medians and percentiles over multiple runs, never a single run. State machine load conditions.
