---
name: e2e-testing
description: Use when writing or maintaining end-to-end tests — Playwright (preferred) or Cypress critical-flow suites. Pattern playbook: page objects, stable selectors, fixtures and isolation, condition-based waiting, flaky quarantine, CI wiring. Backs the e2e-runner agent.
---

# E2E Testing — critical flows, stable and honest

Playbook for functional end-to-end tests. The `e2e-runner` agent does the writing; this skill is the pattern set it follows.

<HARD-RULES>
- Test CRITICAL user journeys (the flows that, broken, mean the product is broken) — not every button. Exhaustive UI coverage is unit/component work, not E2E.
- Selectors: role-based (`getByRole`) or test IDs (`data-testid`) — NEVER brittle CSS/text that breaks on copy changes.
- Wait on CONDITIONS (`expect(...).toBeVisible()`, `waitForResponse`) — never on fixed timeouts (`waitForTimeout`). Timeouts are the #1 source of flake.
- Flaky specs are quarantined and reported, never retried-until-green. A hidden flake is a lie about coverage.
</HARD-RULES>

## Page-object model

- One class/module per page or major component: selectors + actions live there, tests read as user intent (`await loginPage.signInAs(user)`), not selector soup.
- Tests assert outcomes; page objects encapsulate how.

## Fixtures and isolation

- Each test owns its data and starts from a known state (seeded via API/fixtures, not by clicking through setup). No test depends on another's side effects or ordering.
- Auth via storage-state reuse (log in once, reuse the session) rather than logging in through the UI every test.

## Network discipline

- Stub third-party/flaky externals; hit your own backend for real where the journey demands it. Be explicit about which.
- `waitForResponse`/route interception over sleeps.

## Artifacts and CI

- Capture trace + screenshot + video ON FAILURE only (cost). Upload as CI artifacts.
- CI: shard across workers for speed; retries allowed ONLY with a report that surfaces the retried specs (so flake stays visible, not buried).
- The critical-flow subset is the gate; the full suite can be broader.
