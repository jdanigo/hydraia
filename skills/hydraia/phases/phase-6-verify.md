## Phase 6 — Verify & close

Use **verification-before-completion**: actually **run** the project's real build
and test commands (e.g. `ng build`, `npm test`, `go build ./...`, `pytest`) and
read their output. Reviewing logic "inline" or "checking the math by hand" is NOT
verification — if a build/test command exists, you must run it and report the real
result. Confirm the feature meets the spec from Phase 2 (including the threat-model
mitigations), and summarize what shipped. If a build or test fails, the run is not
done — fix and re-run.

**QA matrix check (when `qaFunctional` is on and a QA case doc exists):**
dispatch `qa-automation` (mode: verify) against the case doc. Every case must be
either automated — its `Test ref` points at a real test that ran green in the
build above — or explicitly `manual — <reason>`. Any `pending`, missing ref, or
red case means the run is NOT done: fix and re-verify before closing.

**E2E gate (when `e2eGate` is on AND the repo has an E2E surface):** dispatch
`e2e-runner` (mode: verify), passing the **E2E strategy chosen in the Phase-3 picker**
(`none` / `playwright` / `playwright-testcontainers`, or `customize.toml` `[e2e].strategy`).
It runs the critical-flow suite with the real e2e command; every non-quarantined critical
flow must pass green. A failing critical flow means the run is NOT done — fix and
re-verify. If the strategy is `none`, or the repo has no E2E surface, the gate is skipped
(note it in the run log); never fabricate a suite to satisfy it.

- **`playwright-testcontainers`:** `e2e-runner` first verifies Docker is available and the
  daemon is running (`docker info`). If Docker is absent/stopped, it reports BLOCKED with
  the exact recovery (install/start Docker Desktop, or `sudo systemctl start docker` on
  Linux) — it does NOT silently downgrade to stubbed Playwright or skip the gate. With
  Docker present it spins the real backing services (Postgres/Redis/queues per the spec)
  as ephemeral containers, wires the Playwright suite to them, runs the critical flows,
  and ensures the suite + a CI job that provisions the same containers are committed so
  the gate is reproducible in CI/CD.

**Docs sync (when `docsSync` is on):** dispatch `docs-engineer` (mode: sync). It
updates any README / API docs / CHANGELOG / ADR-index that drifted from the branch's
changed surface and reports what changed. This step never blocks the run — stale
docs do not fail a build; the report tells you what was updated.

**Disarm the gate.** Once the run is verified and done, remove the active-plan
marker so a later unrelated edit is gated again: `rm -f <base>/.active-plan` (where
`<base>` is the resolved artifacts base — `docs/hydraia/` by default, or the external
dir if chosen; removing the in-repo path in external mode leaves the gate armed).
On a genuine blocker that ends the run early, leave the marker so `/hydraia:resume`
can continue without re-arming.

**Emit the run summary.** As the final close step, drop the one-shot marker that tells
the Stop hook to print the transcript-derived run summary (agents dispatched, models
used, real token usage). **Write the summary depth the human chose in Phase 3 step 6
as the marker's content** — `printf 'detailed\n' > <base>/.run-complete` for a
detailed breakdown, or `printf 'brief\n' > <base>/.run-complete` for the compact
box (default), where `<base>` is the artifacts base resolved at the Storage gate
(`docs/hydraia/` by default, or the external dir if chosen). Writing the in-repo path
in external mode drops the marker where `summary.sh` never looks, so the run summary +
telemetry are silently lost. The hook (`hooks/summary.sh`) reads that first line to pick verbosity,
then reads the real numbers from the session transcript plus Claude Code's on-disk
sub-agent transcripts (`<project>/<sessionId>/subagents/agent-*.jsonl`, one per
dispatched sub-agent, with a `.meta.json` naming its `agentType`) — so sub-agent tokens
and models are counted, not just the main session. Do NOT hand-write token or agent
counts yourself; they would be guesses.

**Telemetry logs for EVERY Hydraia route, not just `feature`.** Dropping this marker is
the last action of every route that does real model work — `feature`, `review`,
`resume`, `plan`, `story`, `perf`, `db`, `architect`, and the direct-agent commands
(`e2e`, `devops`, `observability`, `docs`, `graph`). Routes that stop before Phase 6
(e.g. `plan`/`story` at Phase 3, or a one-shot `graph` query) STILL drop the marker at
their end so the run is recorded — use `brief` unless the human explicitly chose
detailed. The Stop hook records only the DELTA since the previous marker this session
(a per-session cursor prevents double-counting when several commands run back to back),
so emitting once per command is correct, never inflating. Only the pure utilities
`dashboard` and `doctor` skip it (no model work to record). The credits line below is
separate: it is printed only for `feature`, `review`, and `resume`.

**Pre-close security gate (mandatory):** run **repo-scan** and **production-audit**
to confirm no hardcoded secrets, no vulnerable dependencies, and no obvious
production-readiness gaps were introduced. Do not report done while a high-severity
item is open. Only then report done. As the very last line of the run summary,
print the credits exactly:

    — Harness By José Daniel Garcés Ospina | Spec Drive Design First —

(Shown on every completed `feature`, `review`, and `resume` run. Not shown for
`plan` or `graph`.)



## NEXT

End of the pipeline chain. `phases/model-policy.md` and `phases/token-discipline.md` are always-on reference (summarized in the dispatcher), not sequential steps.
