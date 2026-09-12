---
name: hydraia
description: Use whenever the user asks to build, add, implement, or change a feature or functionality — or brings a user story or ticket to analyze, reports a bug or unexpected behavior, asks for a branch review, or wants a new app or service designed from scratch. Phase -1 triages the intent and routes it. Runs the complete non-negotiable development pipeline end to end — deep analysis and planning, sub-agent execution, and a double code-review loop — without asking the user which model, skill, or step to use. This is the default way features get built.
---

# Hydraia — Agentic Development Pipeline

This skill defines the ONLY approved way to build a feature. Run every phase, in
order, automatically. **Never ask the user which model, skill, or reviewer to
use — those decisions are already made here.** Never skip a phase. Never pause
for "should I continue?" between phases.

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
- **Autonomy tiers (S/M/L):** derived in Phase -1 from files-touched, `gate.yaml`
  risk overlap, new-logic-vs-mechanical, and UI presence → maps to review depth
  and ceremony. `autoTier=off` → always Tier M. **Never removes the security floor.**
- **Work modes (Quick / Plan / Agile):** a layer over the route, chosen in Phase -1.
  Quick = trimmed ceremony for a tiny change; Plan = today's full single-goal pipeline;
  **Agile** = epic-sized / multi-goal / phased work → decompose into Epic→Stories→Tasks→
  Subtasks+QA, optional one-way Jira sync, then autonomous stage-by-stage execution gated
  by autonomy tier (mechanical stories run solo, tier-L/risky pause). Agile branches
  through `phases/phase-2a-decompose.md` → `phases/agile-orchestrator.md`. Forced by
  `/hydraia:agile` or `customize.toml` `[agile].mode`.
- **Model policy (summary):** this orchestrator session stays **Opus 4.8** for
  judgment (triage, design, plan, both reviews). Execution delegates to the
  Phase-4 executor — **Sonnet 5 by default, overridable via `customize.toml`**.
  Full policy in `phases/model-policy.md`.
- **Execution routing:** Phase 3's picker asks the user how Phase-4 tasks run —
  **Balanced** (Sonnet all), **Economy** (Haiku for mechanical + Sonnet for logic/ui),
  **Max quality** (Opus for logic/ui), or **Hand-off** (freeze the plan, execute later
  on a cheap external runtime). The picker shows a computed recommendation and what each
  option costs/gets. Each plan task carries an `Exec class` (mechanical/logic/ui/qa) that
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
