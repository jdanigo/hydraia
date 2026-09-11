---
name: hydraia
description: Codex-native hydraia pipeline. Use when the user asks to build, add, implement, or change a feature, brings a story/ticket, reports a bug, or wants a branch review. Runs the full spec-drive pipeline on Codex — triage, analyze, spec + threat model, plan + self-review, sub-agent execution, double review, verify — using Codex primitives (apply_patch gate, sub-agents, model routing).
---

# Hydraia (Codex host)

You are running the hydraia spec-drive pipeline on Codex. Host-specific mechanics:

- **Gate:** a `PreToolUse` hook blocks `apply_patch` (and write `shell`) until a plan is
  frozen. Do not fight it — freeze the plan, or set the approval marker with user consent.
- **Sub-agents:** spawn executors for plan tasks (they run `gpt-5.6-luna`, cheap). Spawn
  reviewers at Phase 5 (they run `gpt-5.6-sol`, frontier). This session (plan/spec/design)
  runs `gpt-5.6-sol`.
- **Skills:** invoke supporting skills with `$skill-name`.
- **Step files:** the pipeline body lives in `phases/*.md` next to this file, loaded
  just-in-time. Read one phase file fully, execute it, then load the next only when its
  `## NEXT` directs you. **Never load two phase files at once.** These phase files are
  kept **byte-identical** to the Claude orchestrator's `phases/*.md` (CI enforces per-file
  parity), so they are the shared source of truth that never drifts.

## Host translation table (READ BEFORE the contract)

The contract below (the dispatcher) and the `phases/*.md` it loads are the shared source
of truth, kept byte-identical to the Claude orchestrator so they never drift. They are
written in Claude Code's vocabulary. Wherever a phase file uses a Claude mechanic, execute
the Codex equivalent from this table:

| The contract says (Claude Code) | On Codex, do this |
|---|---|
| `/hydraia:feature`, `/hydraia:story`, `/hydraia:review`, … slash commands | The user invokes `$hydraia`; YOU infer the route in Phase -1 from intent. Treat each `/hydraia:X` as "route = X". |
| "run the **X** skill" / Skill tool | Invoke `$X` (e.g. `$story-analysis`, `$systematic-debugging`, `$performance-tuning`). |
| `AskUserQuestion` | Ask the user inline in plain text and wait for the answer. |
| "dispatch a sub-agent" / Task tool / hydraia-executor | Spawn a Codex sub-agent: **executors** = agent `hydraia-executor` (`gpt-5.6-luna`, cheap) for plan tasks; **reviewers** at Phase 5 = agents `hydraia-reviewer` / `code-reviewer` / `security-reviewer` (`gpt-5.6-sol`, frontier). This orchestrator session runs `gpt-5.6-sol`. |
| named agents (`perf-engineer`, `architect`, `code-architect`, `qa-*`, `db-*`, reviewers) | Spawn the same-named Codex agent if defined under `~/.codex/agents/`; otherwise run that role inline in this session, keeping its model tier (frontier for review/architecture, luna for mechanical execution). |
| `Edit` / `Write` / `apply_patch` before a frozen plan | The `PreToolUse` gate blocks it. Same marker semantics as Claude (frozen plan / `.quick-approved` / `HYDRAIA_ALLOW_DIRECT`). |
| `customize.toml` at `skills/hydraia/customize.toml` | The Codex mirror ships it at `~/.codex/skills/hydraia/customize.toml`; the executor-model / reviewer-panel overrides map onto Codex model routing (luna/sol) the same way. |

Model routing is non-negotiable and identical in spirit to Claude: **cheap `gpt-5.6-luna`
executes, frontier `gpt-5.6-sol` plans/specs/designs/reviews.**

Follow this contract exactly:

<!-- BEGIN PIPELINE CONTRACT -->
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
- **Model policy (summary):** this orchestrator session stays frontier for
  judgment (triage, design, plan, both reviews). Execution delegates to the
  Phase-4 executor — cheap by default, overridable via `customize.toml`.
  Full policy in `phases/model-policy.md`.
- **Execution routing:** Phase 3's picker asks the user how Phase-4 tasks run —
  **Balanced** (Sonnet all), **Economy** (Haiku for mechanical + Sonnet for logic/ui),
  **Max quality** (Opus for logic/ui), or **Hand-off** (freeze the plan, execute later
  on a cheap external runtime). On Codex these map onto the luna/sol tiers (mechanical →
  `gpt-5.6-luna`, judgment → `gpt-5.6-sol`). The picker shows a computed recommendation
  and what each option costs/gets. Each plan task carries an `Exec class`
  (mechanical/logic/ui/qa) that Phase 4 maps to a model. `customize.toml`
  `[executor].routing` can pin a choice and make the run non-interactive.
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
<!-- END PIPELINE CONTRACT -->
