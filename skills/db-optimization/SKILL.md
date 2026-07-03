---
name: db-optimization
description: Use when the bottleneck is database-shaped — slow queries, lock timeouts, connection exhaustion, N+1 patterns, index questions, schema migrations on hot tables. Evidence-first DB playbook for PostgreSQL, MySQL/MariaDB, MongoDB, and Redis backing the db-performance-tuner agent.
---

# DB Optimization — EXPLAIN before you touch anything

Playbook for the DB half of the Hydraia perf route. The `db-performance-tuner` agent does the diagnosis; this skill sets the rules the route runs under.

<HARD-RULES>
- Read-first: no change is proposed without its EXPLAIN plan, stat, or code evidence. Live DB unavailable → code/schema inference only, tagged UNVERIFIED, with the confirming commands listed for the human.
- All write-shaped operations (create index, schema change, config change) are PLAN TASKS — reviewed, gated, never executed by a diagnosis agent.
- Destructive or blocking operations (table rewrites, long locks) are flagged for explicit human approval in the plan; prefer and name the online variant per engine: `CREATE INDEX CONCURRENTLY` (Postgres), `ALGORITHM=INPLACE, LOCK=NONE` (MySQL), rolling index builds (Mongo).
- Schema changes on live tables follow EXPAND-CONTRACT, no exceptions.
- Redact literal data values from any plan/log excerpt that lands in a committed artifact.
</HARD-RULES>

## Expand-contract migration protocol

1. **Expand:** add the new column/table/index alongside the old — additive, backward-compatible, online.
2. **Dual-write + backfill:** application writes both shapes; backfill history in batches (bounded, throttled, resumable).
3. **Switch reads** to the new shape behind a verified flag; watch metrics.
4. **Contract:** only after a full bake period, remove the old shape in a later release. Contract is its own plan task, never bundled with expand.

## Index design guidance

- Composite order: equality columns first, then range, then sort — match the query, not intuition.
- Covering indexes to eliminate lookups for hot read paths; weigh write amplification (every index taxes every write).
- Partial/filtered indexes for skewed predicates (`WHERE deleted_at IS NULL`).
- Hunt UNUSED indexes too (`pg_stat_user_indexes`, `sys.schema_unused_indexes`) — dropping one is also an optimization.
- The index is not always the answer: sometimes it is the query shape, the schema, or the caller (N+1, missing cache).

## N+1 patterns per ORM family

- Detection: a loop in code + per-iteration query in the log/profile. The agent cites the code location.
- Fix families: eager loading (`include`/`select_related`/`prefetch_related`/`preload`), query batching (`IN` lists), dataloader pattern (GraphQL), denormalized read models for hot aggregates.

## Pooling guidance

- Pool size starts near `connections = cores * 2 + effective_spindles` (HikariCP heuristic) — not hundreds; queueing beats connection thrash.
- Always set: acquisition timeout, idle timeout, max lifetime. Connection churn (open/close per request) is itself a finding.

## Per-engine evidence commands

See the db-performance-tuner agent definition for the full read-only evidence list per engine (EXPLAIN variants, stat views, lock views, SLOWLOG). This skill and that agent must stay in sync — update both or neither.
