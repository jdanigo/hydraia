---
description: Generate and run an end-to-end suite for the critical user flows — Playwright, auto-detected, never imposed
argument-hint: <optional focus — e.g. "the checkout journey">
---

Dispatch the **e2e-runner** agent (mode: implement) following the **e2e-testing** skill. Detect the repo's E2E framework from evidence (Playwright/Cypress); if none exists, report it as a plan task rather than installing one. Derive critical user journeys from the acceptance criteria (or the optional focus), write them with page objects, role/testid selectors, and condition-based waits, run the suite, and quarantine any genuine flake with a reason. Report flows written, pass/fail, and quarantined specs.

Focus: $ARGUMENTS

When finished, record telemetry for this run: `printf 'brief\n' > docs/hydraia/.run-complete`. The Stop hook logs this run's real token/model/sub-agent usage to the local dashboard (delta-scoped per session, so it never double-counts). Do not hand-write the numbers.
