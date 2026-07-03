# Changelog

All notable changes to Hydraia are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/).

## [Unreleased]

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
