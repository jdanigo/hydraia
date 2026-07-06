---
description: Instrument logging, metrics, traces, health checks, and alerts — OpenTelemetry-first, never logging secrets or PII
argument-hint: <what to instrument — e.g. "add tracing to the order service">
---

Dispatch the **sre-observability** agent. Add structured logging (correlation IDs), RED/USE metrics, OpenTelemetry traces, health/readiness endpoints, and alert rules as plan tasks. Redaction is absolute — never log secrets, tokens, or PII; review every proposed signal for leakage. Vendor-agnostic: OTel first, vendor SDKs only if already in the repo (never add a new APM dependency). Wiring alerts/dashboards to a live backend is a flagged human step. Report what was instrumented and the redaction decisions.

Request: $ARGUMENTS

When finished, record telemetry for this run: `printf 'brief\n' > docs/hydraia/.run-complete`. The Stop hook logs this run's real token/model/sub-agent usage to the local dashboard (delta-scoped per session, so it never double-counts). Do not hand-write the numbers.
