---
name: hydraia
description: Use whenever the user asks to build, add, implement, or change a feature or functionality — or brings a user story or ticket to analyze, reports a bug or unexpected behavior, asks for a branch review, or wants a new app or service designed from scratch. Phase -1 triages the intent and routes it. Runs the complete non-negotiable development pipeline end to end — deep analysis and planning, sub-agent execution, and a double code-review loop — without asking the user which model, skill, or step to use. This is the default way features get built.
---

# Hydraia — Agentic Development Pipeline

This skill defines the ONLY approved way to build a feature. Run every phase your
level requires, in order, automatically. **Never ask the user which model, skill, or
reviewer to use — those decisions are already made here.** Never skip a step the level
requires. Never pause for "should I continue?" between phases.

Announce once at the start: "Running the Hydraia pipeline." Then proceed silently
through the phases, narrating at most one short line per phase.

## Step-file architecture (how to run this pipeline)

The pipeline body lives in `phases/*.md`, loaded just-in-time. **Read one phase
file fully, execute it, then load the next only when its `## NEXT` directs you.**

- **NEVER load two phase files at once.** Do not skip, reorder, or pre-load phases.
- Follow each phase file exactly, the way you would a step file.
- `phases/model-policy.md` and `phases/token-discipline.md` are always-on
  reference (summarized below), not sequential steps — consult them as needed.

## Always-loaded facts (carry these for the whole run)

- **Route → phases** (decided in Phase -1 triage):
  `feature` 0–6 (full) · `plan` 0–3 then stop · `story` -1–3 (PO-first) ·
  `perf`/`db` -1–6 (measurement-first) · `architect` -1–6 (greenfield) ·
  `review` 5–6 · `graph` codegraph only. Ambiguous route → `AskUserQuestion`.
- **Levels (1 Light / 2 Standard / 3 Deep):** Phase -1 picks ONE level by rule from
  three stated facts — intent gaps, irreversibles, footprint (files, public surface,
  security surface, `gate.yaml` overlap) — and **announces it; it does not ask**.
  Level 1 = one-file spec-plan + one Sonnet executor + judge + `security-scan`;
  Level 2 = spec + plan-contract + Sonnet executors + judge + security floor (default);
  Level 3 = full ceremony. Security surface forces ≥2. The human overrides by saying so
  or via `customize.toml` `[pipeline].level`. **Agile** stays a separate mode for
  epic-sized work (≥2 independent shippable goals) and branches through
  `phases/phase-2a-decompose.md` → `phases/agile-orchestrator.md`.
- **Model policy (summary):** **Opus judges, Sonnet builds.** This orchestrator session
  runs on Opus (any current generation) for triage, design, plan and grading findings.
  Opus sub-agents are only the judges (`hydraia-reviewer`, `security-reviewer`); every
  other agent is pinned to Sonnet, generic agents always get an explicit `model`, and
  executors reach Opus only under Max-quality routing. `hooks/agents.sh` enforces it
  (Opus gate). Full policy in `phases/model-policy.md`.
- **Convergence contract (always on):** a run ends `DONE`, `DONE_WITH_FOLLOWUPS` or
  `BLOCKED(evidence)` — never in an open-ended loop. Pre-existing failures (Phase-0
  baseline) are asked about, never silently fixed. Fixes go through executors
  (`[fix:<slug>]`), never inline edits by this session. Runtime breakers end loops: same
  failure 2× → NO PROGRESS, 3× → STALLED (`hooks/verifyloop.sh`); fix budget and review
  cycles (`hooks/agents.sh`); plan scope (`hooks/blastgate.sh`); plan contract
  (`hooks/plancheck.sh`). When a breaker trips, stop and report — never work around it.
- **Thin orchestrator:** keep this session's context small — dispatches carry pointers
  (plan path + task heading), reviewers read the diff from a file, sub-agent reports are
  short, investigations return summaries. Executors already start clean per task.
- **Execution routing:** computed at Phase 3 and announced (asked only at Level 3) —
  **Balanced** (Sonnet all), **Economy** (Haiku for mechanical + Sonnet for logic/ui),
  **Max quality** (Opus for logic/ui), or **Hand-off** (freeze the plan, execute later
  on a cheap external runtime). The recommendation shows what each option costs/gets. Each plan task carries an `Exec class` (mechanical/logic/ui/qa) that
  Phase 4 maps to a model. `customize.toml` `[executor].routing` can pin a choice and
  make the run non-interactive.
- **Customization:** an optional `customize.toml` overrides the executor routing /
  per-class model / dispatch recipe (read in Phase 4) and the Phase-5 pass-2 reviewer
  panel (read in Phase 5). Precedence: repo `<artifacts-base>/custom/hydraia.toml` >
  global `~/.config/hydraia/custom/hydraia.toml` > shipped `skills/hydraia/customize.toml`.
  Unparseable override → warn and fall back to shipped defaults. **The always-on
  security gate is NOT customizable.**
- **Token discipline** is background and always on (summary in
  `phases/token-discipline.md`): the `caveman` skill compresses internal comms
  only — never code, specs, or plans.

## FIRST STEP

Read fully and follow `phases/phase--1-triage.md` to begin the pipeline.
