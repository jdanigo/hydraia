---
description: Design a new app or service from scratch — guided elicitation, architecture proposals, stack choice, API contract, ADRs — then build it through the full pipeline
argument-hint: <the idea — e.g. "a booking system for small clinics">
---

Invoke the **hydraia** skill forcing the Phase -1 route to **greenfield**. Run the greenfield-architect skill: elicit requirements one question at a time (problem, honest scale, team/constraints, non-functionals, integrations), dispatch the architect + code-architect agents for 2-3 architecture shapes with a recommendation (microservices only with evidence — monolith is the default), confirm the stack with rationale, design the API contract via the api-design skill when an API exists, and record every load-bearing decision as an ADR under docs/hydraia/adr/. Then continue the FULL pipeline (Phases 0-6): spec referencing the ADRs, plan, execution with the matching stack-pattern skill, double review, verify.

To stop at the frozen plan instead of building, use /hydraia:plan with the same idea after the architecture dialogue.

Request: $ARGUMENTS
