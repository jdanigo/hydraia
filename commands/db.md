---
description: Diagnose and fix a database bottleneck evidence-first — EXPLAIN, indexes, N+1, locks, pooling, safe migrations
argument-hint: <symptom or query — e.g. "orders list times out when filtering by date">
---

Invoke the **hydraia** skill forcing the Phase -1 route to **performance (DB-shaped)**. Follow the performance-tuning and db-optimization skills with the db-performance-tuner agent as PRIMARY diagnostician: detect the engine from evidence, collect read-only evidence (EXPLAIN plans, stat views, slow logs — redacting data values), classify findings (index, query shape, N+1, locking, pooling, schema, caching), write the spec with baseline + numeric target, then run the full pipeline. Schema changes follow expand-contract; write-shaped operations are plan tasks, never direct agent actions. Dispatch perf-engineer too only if the evidence points outside the database.

Request: $ARGUMENTS
