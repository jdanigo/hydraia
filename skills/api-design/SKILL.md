---
name: api-design
description: Use when designing or reviewing an API surface — REST, GraphQL, or gRPC. Contract-first methodology: the contract artifact (OpenAPI 3.1, SDL, proto3) is written and reviewed BEFORE implementation, lives in the repo, and Phase 6 verifies implementation matches it.
---

# API Design — the contract IS the spec

Contract-first: write the machine-readable contract, review it like code, implement to it. Never code-first with docs generated after.

## Style selection (decision table — pick ONE, record an ADR)

| Use case | Style |
|---|---|
| Public/partner API, resource-shaped, broad client base | REST + OpenAPI 3.1 |
| Product frontend with many views over the same graph, client-driven field selection | GraphQL + SDL |
| Internal service-to-service, low latency, strong typing across languages | gRPC + proto3 |

Ambiguous → one question to the human with the trade-off, never two styles at once without justification.

## REST rules (OpenAPI 3.1)

- Contract file in-repo: `api/openapi.yaml` (or the repo's existing convention). Reviewed in the same PR discipline as code.
- Resources are plural nouns; no verbs in paths (`POST /orders`, not `/createOrder`). Consistent casing (pick kebab or snake for paths, camel for JSON; record it).
- Methods carry semantics: GET safe, PUT/DELETE idempotent, POST for creation/actions. Idempotency keys for payment-shaped POSTs.
- **Errors:** RFC 9457 `application/problem+json` — every operation lists its error responses in the contract. No bare 500s as design.
- **Pagination:** cursor-based by default; offset only with a written justification (deep-page cost). Filtering/sorting as documented query params.
- **Versioning:** choose URL prefix (`/v1`) or header once, record the ADR, never mix.
- **AuthN/authZ in the contract:** securitySchemes + per-operation scopes/roles. An operation without a declared auth requirement is a finding, not an oversight.

## GraphQL rules (SDL)

- Schema file in-repo. Nullability is design: non-null by intent, not by default.
- Typed errors (union results or errors interface) over throwing strings.
- Pagination: Relay-style connections. N+1: name the dataloader plan at design time.
- Depth/complexity limits stated in the contract docs (abuse surface).

## gRPC rules (proto3)

- Proto files versioned in-repo; packages versioned (`v1`).
- Field numbers are forever: reserve removed numbers, never reuse.
- Deadlines/timeouts and idempotency noted per RPC; streaming only with a stated reason.

## Verification hook (Phase 6)

The implementation must match the contract: routes/fields/status codes vs the contract file (drift check — route list diff, schema validation of real responses where the test suite allows). Contract drift found in verify = the run is not done.
