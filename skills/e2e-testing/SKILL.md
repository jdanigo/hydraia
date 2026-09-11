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

## Browser binaries — never assumed present

Never assume Playwright/Cypress browser binaries are already on the machine. `hooks/doctor.sh --install-e2e --yes` installs the binary for whichever framework the repo already uses (detected from `playwright.config.*`/`cypress.config.*` — it never picks a framework for you), cross-platform (macOS, Linux, Windows-via-WSL), no sudo. The `e2e-runner` agent runs this before every suite in both `implement` and `verify` mode. If it comes back `missing`, that's an environment gap (or, on Linux, missing system libraries that need `install-deps` and sudo) — report it plainly, never silently skip the gate.

## Testcontainers — real backing services, ephemeral (opt-in, needs Docker)

When the run's E2E strategy is `playwright-testcontainers`, the critical flows run against
REAL dependencies (Postgres/MySQL, Redis, Kafka/RabbitMQ, S3-compatible, …) spun up in
throwaway Docker containers, instead of stubbing them. This is the gate that catches what
stubs cannot: schema/migration drift, connection-pool and transaction config, real query
behavior, and cross-service wiring.

<HARD-RULES>
- **Docker is required.** The `e2e-runner` runs `docker info` first; if the daemon is down
  it reports BLOCKED with the recovery — never a silent downgrade to stubs.
- **Use the language's real Testcontainers library** (`@testcontainers/postgresql` etc. for
  Node, `testcontainers` for Python, `org.testcontainers` for JVM, `testcontainers-go`).
  Adding it if absent is a plan decision, not the runner's.
- **Wait on container readiness** with the library's wait strategies (health check, log
  line, port) — never a fixed sleep.
- **Only the services the flows touch.** One known-good state per suite; reuse across specs
  in a run; tear down at the end.
</HARD-RULES>

- **Wiring:** inject the container endpoints into the app-under-test for the test run, run
  the app's real migrations/seeds against the ephemeral DB, then drive Playwright as usual.
- **CI (mandatory here):** Testcontainers manages its own containers, so no `services:`
  block is needed — standard GitHub Actions / GitLab runners already provide Docker. The CI
  job installs deps + the browser (`npx playwright install --with-deps`) and runs the same
  critical-flow command the gate uses. Commit the suite AND the CI job so the gate is
  reproducible off the developer's machine.
