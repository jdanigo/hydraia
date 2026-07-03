# Changelog

All notable changes to Hydraia are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/).

## [Unreleased]

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

[0.2.1]: https://github.com/jdanigo/hydraia/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jdanigo/hydraia/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jdanigo/hydraia/releases/tag/v0.1.0
