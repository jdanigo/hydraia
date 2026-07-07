# Changelog

All notable changes to Hydraia are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/).

## [Unreleased]

## 0.12.0 — 2026-07-07

Guarantees UI work is design-guided end to end. The `ui-ux-pro-max` rule used to
live only in Phase 4 execution — and only as a soft, self-classified "if the task
involves UI" — so visual intent was never set at design time and autonomous
executors fell back to flat, generic output.

- **Phase 2 (design):** the design spec now MUST carry a *UX / visual direction*
  section when the change creates or touches UI — style, palette, type scale,
  spacing/layout, interaction states, and the accessibility floor, decided via
  `ui-ux-pro-max` at design time. Visual quality is set in the spec, not patched
  on at markup-writing time.
- **Phase 3 (plan):** every UI task must embed its concrete visual direction inline
  (per self-containment) instead of pointing at the spec, since a weak autonomous
  executor cannot open it.
- **Phase 4 (execution):** the frontend rule is now a hard gate — not conditional on
  the executor judging a task "UI enough". The `hydraia-executor` agent reports a
  plan defect rather than inventing a generic look when a UI task lacks direction.
- **Enforcement:** `hooks/plancheck.sh` now blocks the spec-drive gate-arm when a
  plan has UI-touching tasks that carry no visual direction, alongside the existing
  self-containment check. Conservative and fail-open, with the `HYDRAIA_ALLOW_DIRECT`
  bypass.

## 0.11.2 — 2026-07-06

Removes an internal editing-workflow reference that leaked into the public
README.

- **Dropped the "Editable source: ... .excalidraw — drag it into excalidraw.com"
  callout** under the pipeline diagram in both README.md and README.es.md. The
  `.excalidraw` source files still ship in `docs/diagrams/` for anyone who wants
  to edit the diagram, but the public docs no longer point at the raw editing
  workflow.
- Docs only — no behavior change.

## 0.11.1 — 2026-07-06

Clarifies where `/hydraia:doctor` and the install commands actually run — several
users tried running them as plain shell commands instead of inside the Claude
Code CLI.

- **`/hydraia:doctor` is a slash command, not a shell command.** README/README.es
  now spell out explicitly: start `claude` in your terminal first, then run
  `/hydraia:doctor` at its prompt — not `hydraia:doctor` or `claude /hydraia:doctor`
  directly in bash/zsh.
- **Two new animated SVG diagrams** (`docs/diagrams/hydraia-doctor-terminal.svg`,
  `docs/diagrams/hydraia-install-terminal.svg`) show a looping terminal demo of
  `claude` → `/hydraia:doctor`, and `claude plugin marketplace add` →
  `claude plugin install`, end to end.
- Docs only — no behavior change.

## 0.11.0 — 2026-07-06

Hydraia now tells you when you are running an outdated version.

- **Version-outdated nudge at session start.** `preflight.sh` (SessionStart hook) now
  checks whether a newer Hydraia has been published and, if so, prints the current and
  latest version plus the exact update commands:

  ```
  [hydraia] update available: v0.10.2 → v0.11.0. Update with:
    claude plugin marketplace update hydraia
    claude plugin install hydraia
  ```

- **Fast and non-invasive.** The latest version is read from
  `.claude-plugin/plugin.json` on `main` via `raw.githubusercontent.com` — the same file
  `marketplace update` pulls. The network fetch is throttled to at most once a day with a
  3-second timeout, so it never slows a session start; offline or on any failure the hook
  stays silent and never blocks. The nudge itself is emitted **every session** — from the
  cached latest version — until the local plugin catches up, then it stops automatically.

## 0.10.2 — 2026-07-06

Telemetry now logs for **every** Hydraia command, not only `feature`.

- **Every route records a run.** The run-complete marker that triggers the Stop-hook
  telemetry is now dropped at the end of every route that does real model work —
  `feature`, `review`, `resume`, `plan`, `story`, `perf`, `db`, `architect`, and the
  direct-agent commands `e2e`, `devops`, `observability`, `docs`, `graph`. Routes that
  stop before Phase 6 (`plan`/`story`, one-shot `graph`) drop it at their own end. Only
  the pure utilities `dashboard` and `doctor` skip it. The credits line is unchanged
  (still only `feature`/`review`/`resume`).
- **Per-session delta cursor (no double-counting).** Because several commands can run in
  one session and `summary.sh` sweeps the whole session transcript, it now records only
  the DELTA since the previous marker this session — tracked by a per-session cursor
  (`~/.cache/hydraia/cursor-<sessionId>.json`) of already-logged message uuids and
  sub-agent files. Running `graph` then `plan` then `review` logs three correct records,
  not three cumulative ones. An emit with no new activity writes nothing.

## 0.10.1 — 2026-07-06

Fixes the sub-agent telemetry capture that 0.10.0 got wrong: agents still showed
`0` and sub-agent tokens were misattributed to the main session.

- **Root cause.** 0.10.0 tried to capture sub-agent usage at `SubagentStop` into a
  repo sidecar. But `SubagentStop` does not fire for every dispatch (e.g. background
  agents), and sub-agent turns are **not** in the main transcript — Claude Code
  persists each sub-agent's full transcript on disk at
  `<project>/<sessionId>/subagents/agent-<id>.jsonl`, with a sibling `.meta.json`
  carrying its `agentType`. The sidecar stayed empty; `summary.sh` then counted any
  in-transcript sonnet turns as *main*, and the agent count fell back to Task blocks
  that a compacted transcript no longer contained → `0`.
- **Fix.** `summary.sh` now reads that on-disk `subagents/` directory directly — one
  agent file = one dispatched sub-agent (the reliable count), its `.meta.json` gives
  the by-type breakdown, and its turns give the real model + token split. It also
  scans sibling session dirs (gated by run-start mtime) so a **compaction** mid-run no
  longer loses the sub-agents. No dependence on the `SubagentStop` hook firing.
- `hooks/agents.sh` reverts to only counting completions for the concurrency cap; the
  sidecar/uuid-dedup machinery is removed. Verified against real on-disk sub-agent
  transcripts: agent count, `agentType`, and per-model in/out/cache all correct.

## 0.10.0 — 2026-07-06

Observability and run-control pass driven by a real production run: the dashboard
was blind to sub-agents, the review ceremony was one-size-fits-all, hung executors
needed manual nudging, functional QA was done in-head instead of as an artifact, and
there was no closing summary choice. All five fixed.

- **Full sub-agent telemetry (the "0 agents / Opus-only" bug).** `hooks/agents.sh`
  now delta-captures each finishing sub-agent's model + token usage at `SubagentStop`
  into a repo-scoped sidecar (`docs/hydraia/.agents/subagents.jsonl`, deduped by entry
  uuid, reset per run) — which survives compaction and session changes, unlike the
  Stop-hook transcript that was silently dropping sub-agent turns. `hooks/summary.sh`
  now merges main-session tokens (swept across every transcript sharing the session
  id) with the sidecar, so the summary and telemetry record report the real agent
  count, the Sonnet execution tokens, and a main-vs-sub split.
- **Dashboard detail.** Telemetry tab shows the true agents-dispatched count, per-model
  **input *and* output** tokens (was input-only), a sub-agent usage panel, agents-by-type,
  and a per-run drill-down (main / sub-agent split). New `heartbeatStaleSecs` and
  `maxTaskRetries` config fields.
- **Per-run review picker (Phase 3).** Before the autonomous half begins, the pipeline
  asks the human for a review depth — **Full** / **Lite** / **Custom** (multi-select of
  optional stages) — so a trivial change need not pay the full double-review ceremony.
  A security floor (`security-scan`, `code-reviewer`, `silent-failure-hunter`,
  `security-reviewer`, one `hydraia-reviewer` pass) always runs; the picker cannot
  remove it.
- **Hung-agent watchdog (Phase 4).** Executors write a heartbeat
  (`docs/hydraia/.heartbeats/<task>`) on start and after each commit. On every wave
  return the pipeline auto re-dispatches ("pushes") any task with no commit and a stale
  heartbeat — up to `maxTaskRetries` (default 2) — instead of waiting for the human to
  poke a stalled agent; exhausted retries surface a real blocker.
- **QA is always a committed document.** The main agent may no longer "apply QA
  itself" — Phase 3 dispatches `qa-functional` to produce and commit
  `docs/hydraia/qa/…-cases.md` (deriving implicit ACs when the spec has no formal
  ones), so the case matrix is reviewable and repo-tracked. The frozen-plan condition
  now requires the committed doc.
- **Closing summary depth.** The human chooses **Brief** or **Detailed** at plan freeze
  (batched with the review picker, keeping Phases 4–6 pause-free); the choice is written
  into the `.run-complete` marker and `summary.sh` renders accordingly — detailed adds
  what shipped, per-agent-type counts, the main-vs-sub token split, and per-model
  in/out/cache.

## 0.9.2 — 2026-07-06

E2E browser binaries become Hydraia-managed instead of an assumed-present
dependency, and the bilingual README split into English (default) + Spanish.

- **`hooks/doctor.sh --install-e2e` (new mode).** Installs the Playwright
  (`npx playwright install chromium`) or Cypress binary for whichever E2E
  framework the repo already picked (detected from `playwright.config.*`/
  `cypress.config.*`/package.json — never chosen by the installer). Same
  no-sudo, cross-platform pattern as the `codegraph`/`markitdown` installers
  (macOS, Linux, Windows-via-WSL). `--check` now also reports the detected
  framework and whether its browser binary is cached.
- **`e2e-runner` agent** runs `doctor.sh --install-e2e --yes` before writing or
  running any suite (both `implement` and `verify` modes) and reads its
  `RESULT e2e_framework=… e2e_browsers=…` line — `missing` surfaces the exact
  recovery command (including the sudo-gated `install-deps` case on Linux)
  instead of silently failing mid-run.
- **`/hydraia:doctor` command** and the `e2e-testing` skill document the new
  opt-in install path; README prerequisites table gains the browser-binaries
  row.
- **`README.es.md` (new).** Full Spanish translation, faithful 1:1 with
  `README.md` (code/commands/names untouched). `README.md` stays the default;
  both files cross-link via a language switcher at the top.

## 0.9.1 — 2026-07-04

Hard self-containment guarantee: any cheap, context-less executor (Haiku,
Sonnet 5, Gemini Flash, Codex) can run a frozen plan from the task block alone —
enforced at runtime, not just asked of the planner.

- **`plancheck.sh` hook (new, PreToolUse on Bash).** When the pipeline arms the
  spec-drive gate, this hook scans the frozen plan's task bodies for reference
  smells — "follow spec §X", "see the design", "as in the spec", section
  pointers — and BLOCKS the arm if the plan is not self-contained. A plan that
  would make a cheap executor guess, truncate, or improvise cannot reach Phase 4.
  Fail-open on error; `HYDRAIA_ALLOW_DIRECT=1` overrides a false positive.
- **Contract: never reference the spec/other docs/other code for content.** The
  plan must inline the literal content into each task even though it duplicates the
  spec — DRY yields to self-containment, because the executor cannot open the spec.
  This is what makes the plan a genuinely portable hand-off artifact.
- **Contract: state each task's execution environment.** Exact command, working
  directory, dependency/service preconditions, and named prior-task outputs — a
  cheap executor assumes nothing from context.
- **Contract: verify completeness of large literals** (line-count / last-line
  assert), not just file existence — catches a truncated verbatim block.
- **Self-review Pass A** gains explicit rejects for spec-referencing, missing exact
  commands, unnamed task dependencies, and existence-only checks on big literals.

## 0.9.0 — 2026-07-04

Efficiency + reliability pass: cut per-run token cost and close a real
subagent-trust gap. No new components — pure pipeline-contract tightening.

- **Phase 5 reviewers scoped to the diff.** The review panel no longer dispatches
  every reviewer on every run — `security-reviewer`, `silent-failure-hunter`, and
  `code-reviewer` always run; language reviewers run only when their file types are
  actually in the diff. Running six Opus reviewers on a two-file change was the
  biggest avoidable per-run cost; it is now routed by changed surface.
- **Model tiers in review.** Correctness/security-bearing reviewers stay on Opus;
  mechanical passes (style/lint/doc-comment) drop to Sonnet/Haiku. Opus is spent
  only where judgment pays.
- **Findings deduped before triage.** Pass 1, Pass 2, and the security skills
  overlap; findings are now collapsed by (file, line, root cause) so triage tokens
  are spent once per real problem, not once per report.
- **Phase 4 verifies each task landed in git before the next wave.** A subagent
  report is no longer trusted as proof — `git log`/`git status` confirm the commit
  exists before building on it, catching the "reported done but didn't commit"
  failure at the wave boundary instead of at Phase 6.
- **Phase 3 self-review hardened for cheap-model execution.** The plan contract now
  enforces the "Haiku test": every task must embed literal file content (not a
  description of it), give exact `old_string`→`new_string` edits anchored by unique
  quoted text (never bare line numbers), carry a runnable verification with expected
  output, contain no placeholders (`TODO`/`TBD`/"similar to Task N"), and keep
  names/signatures consistent and resolvable across tasks. A fully-specified plan
  executes in one shot on Sonnet/Haiku instead of forcing a re-dispatch or Opus
  rescue — the token-economy win moves into the contract, not the planner's memory.
- **README:** the "how it works" circuit and per-phase skill table now reflect
  Phase -1 routing, the QA/E2E/docs Phase 6 gates, diff-scoped review, and all
  wave-1/2 commands.

## 0.8.0 — 2026-07-04

Engineering-team expansion, wave 2: delivery — E2E, docs, DevOps, observability.
Completes the 8-agent / 9-skill roadmap.

- **e2e-runner agent (Sonnet):** Playwright/Cypress critical-flow E2E, framework
  auto-detected (never imposed), flaky quarantine. Phase 6 gate — a failing
  critical flow fails the run; skipped cleanly when no E2E surface exists.
- **docs-engineer agent (Sonnet):** syncs README / API docs / CHANGELOG / ADR
  index with the code surface; Phase 6 updates and reports drift, never blocks.
- **devops-engineer agent (Sonnet):** CI/CD, Docker, IaC following the repo's
  platform; deploy/secrets/destructive infra flagged for human approval, never
  executed by the agent.
- **sre-observability agent (Sonnet):** structured logging, RED/USE metrics, OTel
  traces, health checks, alerts; OTel-first, never logs secrets or PII.
- **e2e-testing skill:** Playwright playbook — page objects, role/testid
  selectors, condition-based waits, flaky quarantine, CI sharding.
- **/hydraia:e2e, :devops, :observability, :docs commands**; Phase 6 E2E gate +
  docs sync; `e2eGate` and `docsSync` config keys (default on).
- Design spec: `docs/hydraia/specs/2026-07-04-devops-docs-e2e-observability-design.md`.

## 0.7.0 — 2026-07-03

Engineering-team expansion, wave 1C: greenfield architecture + contract-first APIs.

- **greenfield-architect skill:** interactive from-scratch design — one-question-
  at-a-time elicitation (problem, honest scale, team, non-functionals),
  architecture proposals via the architect agents (monolith default,
  microservices only with evidence), confirmed stack, anti-overengineering rules.
- **api-design skill:** contract-first REST/GraphQL/gRPC — OpenAPI 3.1, RFC 9457
  errors, cursor pagination, per-operation auth in the contract, Phase 6 drift
  check.
- **adr skill:** MADR-lite decision records under `docs/hydraia/adr/` with
  supersede lifecycle; every load-bearing decision recorded.
- **node-patterns and dotnet-patterns skills:** builder playbooks giving TS/Node
  and C#/.NET the same prevention-side coverage React/Go/Spring/Python had.
- **/hydraia:architect command**; greenfield route in Phase -1 upgraded; Phase 4
  stack rule extended.
- Design spec: `docs/hydraia/specs/2026-07-03-greenfield-architect-design.md`.

## 0.6.0 — 2026-07-03

Engineering-team expansion, wave 1B: measurement-first performance + DB tuning.

- **perf-engineer agent (Opus):** baseline-or-bust diagnosis — profile, rank
  bottlenecks by measured contribution (USE/RED), hypotheses with expected
  gains and blast radius; read-only.
- **db-performance-tuner agent (Opus):** evidence-first DB tuning across
  PostgreSQL, MySQL/MariaDB, MongoDB, Redis — EXPLAIN plans, index design,
  N+1, locking, pooling; write-shaped changes become plan tasks.
- **performance-tuning skill:** the perf route contract — no optimization
  without a baseline, numeric target in the spec, Phase 6 re-measures with
  the same commands; one isolated change per task.
- **db-optimization skill:** EXPLAIN-first playbook — index design guidance,
  N+1 fix families, pooling sizing, expand-contract migration protocol,
  online-DDL variants per engine.
- **/hydraia:perf and /hydraia:db commands**; Phase -1 wave-B placeholder
  replaced with the live route.
- Design spec: `docs/hydraia/specs/2026-07-03-perf-db-tuning-design.md`.

## 0.5.0 — 2026-07-03

Engineering-team expansion, wave 1A: product + QA + intent routing.

- **Phase -1 intent triage** in the pipeline contract: plain-language requests are
  classified (feature · user story · bug · perf/DB · greenfield · review) and
  routed; ambiguous intent asks instead of assuming. Explicit commands force
  their route.
- **story-analysis skill (Product Owner):** INVEST check, epic splitting,
  one-at-a-time ambiguity questions, numbered acceptance criteria (AC-n), story
  artifact under `docs/hydraia/stories/`.
- **qa-functional agent (Sonnet):** Given/When/Then cases per AC + traceability
  matrix under `docs/hydraia/qa/`; spec gaps reported, never guessed. Plan
  cannot freeze while an AC lacks a case and a task.
- **qa-automation agent (Sonnet):** implements cases in the repo's existing test
  framework (Phase 4) and verifies full matrix coverage in Phase 6 — any
  uncovered case fails the run.
- **/hydraia:story command:** story → PO analysis → spec → QA cases → frozen
  plan, then stop (mirror of /hydraia:plan).
- **qaFunctional config key** (default on) honored by the pipeline and editable
  from the dashboard.
- Design spec: `docs/hydraia/specs/2026-07-03-product-qa-router-design.md`.

## [0.4.1] — 2026-07-03

### Changed
- **Dashboard redesigned to a premium, AI-dev-tool aesthetic** (via the
  `ui-ux-pro-max` design system: Dark Mode OLED, green accent, Inter-style system
  stack — still zero external fonts/CDN). Left sidebar navigation with inline SVG
  icons (no emoji), KPI cards with colored icon chips, status pills with check/x
  glyphs (never color-only), a token-volume sparkline, gradient bar charts, tabular
  figures, custom toggle switches, visible focus rings, loading skeletons, a
  `prefers-reduced-motion` guard, and a responsive sidebar→top-bar collapse. All
  existing data bindings and the config POST are unchanged. Verified in-browser
  across all three tabs with no console errors.

## [0.4.0] — 2026-07-03

### Added
- **Local dashboard** (`/hydraia:dashboard`, `dashboard/server.js` +
  `dashboard/index.html`). A zero-dependency Node server (built-ins only) bound to
  **`127.0.0.1`** — never exposed to the network, all data stays on the machine.
  Three tabs:
  - **Status** — plugin version, every installed skill and agent (with
    descriptions), hook events, detected MCP servers, and dependency health.
  - **Telemetry** — usage recorded **locally** per completed run (runs, agents,
    tokens in/out, tokens by model, skills used, runs by day, recent-runs table).
    Charts are hand-rolled inline; nothing is ever transmitted.
  - **Config** — edit the run modes in a form and save; writes
    `~/.config/hydraia/config.json`.
- **Local usage telemetry.** The run-summary Stop hook now appends one JSON record
  per completed run to `~/.cache/hydraia/telemetry.jsonl` (transcript-derived: agents,
  models, real tokens, skills). Local-only, on by default, and disableable from the
  dashboard.
- **Config system** (`hooks/config.sh`). Hooks now resolve run modes with the
  precedence **env override > per-repo `docs/hydraia/config.json` > global
  `~/.config/hydraia/config.json` > built-in default**. Enforced deterministically by
  the hooks: agent caps (`maxConcurrentAgents`, `maxTotalAgents`), `specDrive`
  (`strict`/`relaxed`/`off`), `telemetry`, `runSummary`, `codegraphAuto`. Prompt-level
  modes (`autoInstallDeps`, `reviewMode`, `selfReviewPasses`, `securityGates`,
  `pdfConversion`, `cavemanInternal`) are read and honored in Phase 0. The
  un-forgeable `HYDRAIA_ALLOW_DIRECT` bypass is deliberately **not** file-configurable.

## [0.3.1] — 2026-07-03

### Fixed
- **Auto-install hardened to work end-to-end on macOS, Linux, and Windows** — the
  0.3.0 offer could silently no-op on common real-world setups. `doctor.sh --install`
  now:
  - resolves Python across platforms (`python3` / `python` / the Windows `py -3`
    launcher) and installs via `python -m pip`, not a bare `pip` that may not exist;
  - installs **markitdown with pipx** (isolated CLI, non-interactive `ensurepath`
    fixes PATH itself), bootstrapping pipx when absent, and falls back to
    `pip --user` with a `--break-system-packages` retry for **PEP 668
    "externally-managed"** environments (Homebrew Python, Debian 12+, Ubuntu 23+,
    Fedora) where the old `pip install` hard-failed;
  - installs **codegraph with npm**, retrying in a **user-owned prefix** on an
    `EACCES` permission error instead of failing — **never uses sudo**, so it can't
    hang on a password prompt;
  - **verifies** what actually landed and prints a machine-readable
    `RESULT codegraph=… markitdown=…` (`ok` / `installed` / `missing`). Phase 0 reads
    it and never re-offers a completed install nor loops on a failed one.
- **Cache dir created before the installers use it.** On a fresh `HOME`,
  `~/.cache/hydraia` did not exist when `install_codegraph` redirected npm's stderr
  to a log there, so npm never ran and codegraph came out `missing`. `mkdir -p` up
  front.
- **CI now proves it.** A new `install-e2e` matrix job runs the real installer on
  `ubuntu-latest`, `macos-latest`, and `windows-latest` on every push and fails if
  either tool ends up `missing`.

Verified end-to-end: **macOS** (`RESULT codegraph=ok markitdown=ok`) and **Linux**
(Ubuntu 24.04, PEP 668 externally-managed → `codegraph=ok markitdown=installed`,
both resolving in a fresh shell). Windows is covered by the same code paths and the
CI matrix; run the matrix to confirm on that OS.

## [0.3.0] — 2026-07-03

### Changed
- **Zero-touch dependency install.** Users complained that getting the external
  tools running meant knowing about and manually running `/hydraia:doctor`. Now the
  pipeline handles it: **Phase 0 detects missing managed binaries and offers to
  install them inline, once, via `AskUserQuestion`** (one click — *Install now* /
  *Skip this run*), then runs the bundled installer. Nothing to memorize. On approval
  it installs; on skip it degrades gracefully and does not nag again that run. If a
  system runtime is missing (`npm`/`pip`/`node`/`python3`/`git` — which a plugin must
  not auto-install), it surfaces `doctor --check` with copy-paste hints instead of
  silently failing.
- **`doctor.sh` prints per-OS install commands** for the prerequisites it can't
  install — `brew` on macOS, `apt`/`dnf` on Linux, `winget` on Windows, with a
  download-URL fallback — so the manual part is copy-paste, not a scavenger hunt.
- **`preflight.sh` persists the plugin root** (`~/.cache/hydraia/plugin-root`) at
  session start, because `CLAUDE_PLUGIN_ROOT` is not set for the model's shell — this
  is what lets Phase 0 locate and run the bundled installer on its own.

## [0.2.3] — 2026-07-03

### Fixed
- **Code graph never bootstrapped on a fresh project.** The session-start hook ran
  `codegraph index .` when no index existed, but `index` requires an initialized
  project — so `.codegraph/` was never created and the graph silently stayed empty
  (the pipeline then ran on blind file reads). `hooks/preflight.sh` now keys on the
  `.codegraph/` directory: **absent → `codegraph init <repo-root>`** (initialize +
  build the initial index, recursively covering every subfolder), **present →
  `codegraph sync <repo-root>`** (fast incremental). The initial index runs in the
  background so session start is never blocked, and it targets the git repo root so
  one index covers all subfolders (never one per subfolder).
- **Phase 0 no longer assumes the graph exists.** `SKILL.md` claimed the pre-flight
  sync had already run and told the model to query the graph unconditionally — false
  on a machine without codegraph or during a first-run index. Phase 0 now degrades
  gracefully: use the graph when available, otherwise fall back to targeted file
  reads and suggest `/hydraia:doctor` once. codegraph is an accelerator, not a hard
  requirement.

## [0.2.2] — 2026-07-03

### Added
- **Agent budget** (`hooks/agents.sh`, PreToolUse on `Task` + SubagentStop): bounds
  the blast radius of Phase 4 so a plan with many tasks cannot fan out into an
  unbounded swarm of sub-agents and burn a usage window. Two runtime caps, enforced
  only during an active run (fresh `docs/hydraia/.active-plan`) in Hydraia repos:
  - **Total per run** — `HYDRAIA_MAX_AGENTS` (default 30). The hard guarantee: every
    dispatch is counted under a portable `mkdir` lock, so even a same-turn burst of
    100+ `Task` calls is serialized and cut off at the ceiling. A blocked dispatch
    is not counted (so it cannot poison the in-flight tally).
  - **Concurrent in flight** — `HYDRAIA_MAX_CONCURRENT` (default 6). Best-effort
    throttle: `in_flight = dispatched − finished`, finished counted from
    SubagentStop. If that completion signal never arrives, the concurrency check
    self-disables so a run can never deadlock — the total cap still bounds it.

  Ceilings are the human's to raise (`export HYDRAIA_MAX_AGENTS=50`), never the
  model's; `HYDRAIA_ALLOW_DIRECT=1` lifts both. `SKILL.md` Phase 4 now dispatches in
  bounded waves and Phase 3 requires right-sized (consolidated) tasks so plans stay
  well under the ceiling by design.

## [0.2.1] — 2026-07-03

### Fixed
- **Duplicate hooks file error on load.** `plugin.json` declared
  `"hooks": "./hooks/hooks.json"`, but Claude Code already auto-loads the standard
  `hooks/hooks.json` by convention — so the manifest reference loaded it a second
  time and the plugin failed with "Duplicate hooks file detected." Removed the
  `hooks` key from the manifest; the standard hooks file (SessionStart, PreToolUse,
  Stop) still loads automatically. The `manifest.hooks` field is only for
  *additional* hook files.

## [0.2.0] — 2026-07-03

Spec-drive, enforced. This release makes "never skip a phase" a runtime guarantee
(not just a prompt), restores design-first with a written spec, splits the pipeline
into an interactive design half and an autonomous execution half, and adds a
transcript-derived run summary at close.

### Added
- **Spec-drive gate** (`hooks/gate.sh`, PreToolUse on `Edit`/`Write`/`MultiEdit`):
  blocks source-code edits until Phase 3 freezes a plan (`docs/hydraia/.active-plan`
  marker), making "never skip a phase" a runtime guarantee instead of a prompt the
  model can rationalize past. Enforced only in repos that use Hydraia (a
  `docs/hydraia/` directory); markdown and pipeline artifacts are exempt.
- **Human-only bypass** `HYDRAIA_ALLOW_DIRECT=1`: the decision to skip the pipeline
  for a trivial change is the human's, set as an env var — never the model's.
- **Run summary** (`hooks/summary.sh`, Stop hook): at the end of a completed
  pipeline run, prints a transcript-derived summary — sub-agents dispatched (with
  their types), skills invoked, models used, and real token usage
  (input/output/cache-read).
  Numbers come from the session transcript (`message.usage` / `message.model`),
  never from the model self-reporting, which would hallucinate counts. Gated on a
  one-shot `docs/hydraia/.run-complete` marker written by Phase 6, so it fires only
  when a run actually finishes — not after every turn. No cost estimate by design;
  tokens, agents, and models only.
- **Quick-mode** (`docs/hydraia/.quick-approved`, 30-min single-burst marker): on a
  strictly trivial change (no new logic/file, no security surface), the model may
  ask via `AskUserQuestion` whether to skip the design ceremony. Only an explicit
  human approval lets it proceed, and it still runs the real build/tests and commits.
  Changes touching auth/PII/external input are never Quick-mode eligible, so the
  threat model is never skipped.

### Changed
- `SKILL.md` hardened: token cost / change size are explicitly forbidden as reasons
  to skip a phase; Phase 6 must run the real build/tests (not inline reasoning);
  Phase 3 arms and Phase 6 disarms the gate marker.
- **Two modes: design dialogue, then continuous execution.** "Never pause" was
  over-scoped — it capped the whole run to a single clarifying question, which
  strangled brainstorming and made the pipeline jump straight from prompt to code.
  Now Phases 1–3 (think → design → plan) are **interactive**: real brainstorming
  dialogue, approaches, and a mandatory design-approval gate before the spec is
  written. "Continuous execution / never pause" applies only to Phases 4–6
  (execute → review → verify), once the plan is frozen. `feature.md` and `plan.md`
  updated to match.
- **Design-first restored.** Phase 2 now requires a **written** design spec
  (`docs/hydraia/specs/`) — goal, chosen vs rejected approaches, code-graph anchors,
  global constraints, threat model — as a mandatory artifact, not inline reasoning;
  Phase 3 cannot start and the gate cannot be armed until it exists. Phase 3 now
  restates the full `writing-plans` structure (per-task `Files:` with exact
  paths/line-ranges, `Interfaces:`, bite-sized TDD steps) and the self-review
  rejects any plan whose tasks lack file-level detail. Closes the regression where
  autonomous runs collapsed design into a thin plan.
- README: added "Why Hydraia", "Standout capabilities", and "Plan once, execute
  anywhere" (multi-agent cost/parallelism workflow); expanded use cases; removed the
  one-time `publish.sh` bootstrap in favor of GitHub fork + `marketplace add`.

## [0.1.0] — 2026-07-02

First public release. Hydraia is a self-contained agentic development harness for
Claude Code: one command runs the full feature pipeline (context → think → design
+ threat model → plan + self-review → sub-agent execution → double code review →
verify) with security gates throughout.

### Added
- **Self-contained plugin.** Every skill (31) and agent (14) the pipeline uses
  ships inside the plugin under `skills/` and `agents/` — no external plugin
  dependencies.
- **`/hydraia:doctor`** + `hooks/doctor.sh` (`--check` / `--install`): validates
  prerequisites and installs/updates `codegraph` and `markitdown` to latest, with
  user consent.
- **`/hydraia:resume`** + run log (`docs/hydraia/runs/`): continue an interrupted
  pipeline from the last incomplete phase.
- **Commands:** `feature`, `plan`, `review`, `graph`, `doctor`, `resume`.
- **Model guard:** warns once if the session is not on Opus 4.8 and explains the
  Opus-plans / Sonnet-executes split; never blocks.
- **Continuous execution:** the pipeline runs every phase to completion without
  pausing between phases.
- **Credits line** printed on every completed run.
- **Security gates** at three points: design threat model, review
  (`security-scan` + `security-review` + stack-specific), and pre-close
  (`repo-scan` + `production-audit`).
- **Session hook** `hooks/preflight.sh`: codegraph sync + daily, non-invasive
  dependency nudge.
- **Install surface:** `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`.
- **Open-source packaging:** root MIT `LICENSE`, `NOTICE`, per-upstream licenses
  in `LICENSES/`, `CONTRIBUTING.md`, and a CI workflow validating manifests, bash
  syntax, discovery counts, and license completeness.

[0.4.1]: https://github.com/jdanigo/hydraia/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/jdanigo/hydraia/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/jdanigo/hydraia/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/jdanigo/hydraia/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/jdanigo/hydraia/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/jdanigo/hydraia/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/jdanigo/hydraia/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jdanigo/hydraia/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jdanigo/hydraia/releases/tag/v0.1.0
