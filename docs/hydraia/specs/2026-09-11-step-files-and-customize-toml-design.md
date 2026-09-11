---
status: draft
date: 2026-09-11
route: feature
topic: step-files + customize.toml
spec_version: 1
---

# Design — Step-file pipeline + `customize.toml` override layer

## Goal

Two BMAD-inspired upgrades to the Hydraia orchestrator, chosen for token economy
and extensibility **without sacrificing the runtime guarantees Hydraia already has
over BMAD** (loop-hardening, spec-drive gate, telemetry, three security gates):

1. **Step-file architecture (#1).** Split the 806-line monolith
   `skills/hydraia/SKILL.md` into a thin **dispatcher** plus per-phase files
   (`phases/*.md`) loaded just-in-time. The orchestrator (Opus 4.8, the most
   expensive model in the run) stops carrying all seven phases in context on
   every turn.

2. **`customize.toml` override layer (#2).** A declarative file, read by the
   orchestrator, that overrides the **executor model / dispatch recipe** and the
   **Phase-5 reviewer panel** per repo — without editing the skill or forking.
   This is the mechanism that turns Hydraia's fixed Sonnet executor into
   "pin Haiku for mechanical work" or "route the executor to Codex/Gemini/an
   external CLI", which is precisely the lever behind BMAD's cheap-execution
   reputation.

### Non-goals (YAGNI)

- No change to the phase *semantics* — the contract text is preserved verbatim
  when moved into phase files. This is a pure re-organization + a new override
  read, not a rewrite of the pipeline.
- No new runtime dependency in the fail-open bash hooks. The override values are
  consumed by the orchestrator (an LLM reading a file), never parsed in bash.
- Not shipping the full BMAD `customize.toml` surface (`activation_steps`,
  `persistent_facts`, `on_complete`, `open_spec`). Those are largely already
  covered in Hydraia by `constraints.md` + hooks; the schema reserves their
  tables for later but the resolver ignores unknown keys.

## Chosen approach

### #1 — Dispatcher + `phases/*.md`, Codex mirrors (per-phase parity)

Single source of truth for the pipeline contract becomes a set of phase files:

```
skills/hydraia/
  SKILL.md            # dispatcher: frontmatter + preamble + global facts + JIT loader
  phases/
    phase--1-triage.md
    guards.md          # start-of-run guards
    model-policy.md    # global model policy (always loaded — small, cross-phase)
    phase-0-context.md
    phase-1-think.md
    phase-2-design.md
    phase-3-plan.md
    phase-4-execute.md
    phase-5-review.md
    phase-6-verify.md
    token-discipline.md
```

- **Dispatcher (`SKILL.md`)** keeps: the YAML frontmatter (name/description —
  unchanged, this is the plugin skill entry), a short preamble, the small
  **always-loaded global facts** (route→phase map, autonomy-tier definitions,
  model policy pointer), and the **JIT loader rule**: read one phase file fully,
  execute it, load the next only when directed. Mirrors BMAD `workflow.md`.
- **Phase files** hold the heavy execution detail, moved **verbatim** from the
  current SKILL.md line ranges. `NEVER load two phase files simultaneously`.
- **Codex side mirrors per-phase.** `codex/skills/hydraia/phases/*.md` are
  **byte-identical** copies of the Claude phase files. The Codex `SKILL.md`
  keeps its host-translation table + the `BEGIN/END PIPELINE CONTRACT` markers
  around its dispatcher, so the existing CI presence check still passes.
- **CI upgrade (parity now enforced, not just intended):** add a step that
  asserts, per file, `skills/hydraia/phases/X.md` == `codex/skills/hydraia/phases/X.md`
  (`diff -q`). This is stronger than today's presence-only check and directly
  implements "Codex espeja … CI drift compara por-fase".

**Global facts stay in the dispatcher** precisely because Hydraia's phases are
not as independent as BMAD's steps (Phase -1's route/tier choice conditions later
phases; model policy is global). Keeping those few small facts always-loaded, and
only the heavy per-phase bodies JIT, preserves correctness while capturing the
context saving. Phase 3 alone is ~200 lines that no longer sit in context during
Phases 0–2 and 4–6.

### #2 — `customize.toml` read by the orchestrator

```
skills/hydraia/customize.toml           # defaults, "DO NOT EDIT — overwritten on update"
<artifacts-base>/custom/hydraia.toml     # per-repo override (git-committed if in-repo)
~/.config/hydraia/custom/hydraia.toml    # global override
```

- Precedence (documented, applied by the orchestrator when it reads them):
  **repo override > global override > shipped defaults**. Mirrors the existing
  `hy_config` precedence philosophy (env > repo > global > default) so there is
  one mental model.
- **Consumed by the orchestrator only.** Phase 4 reads `[executor]` before
  dispatching; Phase 5 reads `[[reviewers]]` before building the panel. The bash
  hooks never read this file → no TOML parser in bash, no new fail-open dep.
- **Merge rules** (documented in the file header, same as BMAD): strings replace;
  lists append; tables merge key-by-key; arrays-of-tables merge by `id`
  (matching `id` replaces a default layer, new `id` appends).

Minimal-extensible schema (v1):

```toml
[executor]
# Model the Phase-4 executor runs on. Drop to "haiku" for mechanical work, or
# leave "sonnet" (Hydraia default). The orchestrator passes this as the model
# when it dispatches hydraia-executor.
model = "sonnet"

# Optional full override of the dispatch recipe. Empty = default subagent
# dispatch (fresh hydraia-executor per task, spec/task block only). A non-empty
# value is followed verbatim, e.g. route the task to an external CLI via bash.
# {task_block} and {graph_context} are substituted at run time.
handoff = ""

# Phase-5 pass-2 reviewer panel. Array-of-tables merged by id. Omit to keep the
# shipped panel. Set instruction = "" to disable a shipped layer by id.
[[reviewers]]
id = "correctness"
model = "opus"
# instruction = "..."   # optional override of the layer's dispatch prompt

# Reserved for a later version — resolver/orchestrator ignores unknown tables:
# [workflow] activation_steps / persistent_facts / on_complete
```

- **Executor model override** requires Phase 4 to pass a model when dispatching.
  The `hydraia-executor` agent frontmatter keeps `model: sonnet` as the default;
  the Agent/Task dispatch overrides it with `[executor].model` when set. No new
  agent variants.
- **doctor.sh** reports presence + which override files are active (read-only
  presence report — it does not parse the TOML).

## Rejected alternatives

- **#1 "Solo extraer, contrato intacto"** — moving bodies out but keeping the
  full contract block inline defeats the token goal (the contract is the bulk).
  Rejected: no real saving.
- **#1 "Full fragment both sides, no dispatcher"** — no always-loaded global
  facts risks the orchestrator losing route/tier/model context mid-run. Rejected:
  correctness risk for Hydraia's coupled phases.
- **#2 JSON in existing `config.json`** — would reuse `hy_config` with zero new
  files, but the user explicitly wants `customize.toml` (BMAD parity) and TOML is
  already CI-validated with `tomllib`. Array-of-tables reviewer panels read far
  better in TOML. Kept JSON's precedence model, chose TOML's surface.
- **#2 bash TOML parser** — rejected outright: adds a hard dep to fail-open hooks.
  Orchestrator-read sidesteps it entirely.

## Code-graph anchors (files touched)

- `skills/hydraia/SKILL.md` — becomes dispatcher (phase bodies removed to `phases/`).
- `skills/hydraia/phases/*.md` — **new**, verbatim phase bodies.
- `skills/hydraia/customize.toml` — **new**, shipped defaults.
- `codex/skills/hydraia/SKILL.md` — dispatcher + translation table; contract
  markers wrap its loader.
- `codex/skills/hydraia/phases/*.md` — **new**, byte-identical mirror.
- `hooks/doctor.sh` — report customize override presence.
- `.github/workflows/ci.yml` — per-phase parity `diff`; TOML validate `customize.toml`.
- `README.md` / `README.es.md` / `CHANGELOG.md` — document both features.
- Phase 4 body (`phase-4-execute.md`) — read `[executor]`; Phase 5 body
  (`phase-5-review.md`) — read `[[reviewers]]`.

## Global constraints

- **No AI attribution in commits** (`Co-Authored-By`/AI trailer forbidden — repo rule).
- Phase bodies moved **verbatim**; any wording change is a separate, called-out edit.
- Codex phase files must stay byte-identical to Claude phase files (CI enforces).
- Do not weaken any security gate, the spec-drive gate, or loop-hardening.
- Hooks remain fail-open and dependency-free at runtime.

## Threat model + mitigations

| Risk | Vector | Mitigation |
|---|---|---|
| Fragmentation drops/duplicates contract text | manual move error | CI per-phase parity diff; a full-run smoke read; `git diff` review that concatenated phase files == old contract content |
| Codex/Claude phase drift over time | future edits touch one side | new CI `diff -q` per phase file — hard fail |
| `customize.toml` used to weaken security | repo override disables security reviewers | override applies to Phase-5 **pass-2 panel only**; the always-on `security-scan`/`security-review` gate is NOT customizable (documented + enforced in phase-5 body) |
| Executor pointed at untrusted external tool via `handoff` | supply-chain / exfil | `handoff` runs under the same blast-gate + spec-drive hooks; documented as user-owned risk; default empty |
| TOML syntax error breaks a run | bad override | orchestrator falls back to shipped defaults on unparseable override and warns; doctor reports presence |
| Dispatcher loses global context mid-run | over-fragmentation | route map + tier defs + model policy stay always-loaded in dispatcher |

## Success criteria

- `skills/hydraia/SKILL.md` ≤ ~120 lines; each phase body lives in its own file.
- Concatenating the phase files (in order) reproduces the current contract content
  (verbatim, verified by diff of normalized text).
- CI green: per-phase Claude↔Codex parity diff passes; `customize.toml` validates
  as TOML; existing contract-presence + shell-gate checks still pass.
- A repo `customize.toml` with `[executor] model = "haiku"` causes Phase 4 to
  dispatch executors on Haiku (verified by a dry-run trace / telemetry model line).
- A repo `customize.toml` adding a `[[reviewers]]` layer causes Phase 5 to launch
  it; setting a shipped layer's `instruction = ""` disables it.
- Security gate remains non-customizable and always runs.
- `doctor.sh` shows customize-override presence.

---

# Increment 2 — Interactive execution routing + brainstorming right-sizing

## Goal

Give Hydraia full, precise control over which model executes each Phase-4 task —
Haiku / Sonnet / Opus per task **class**, or hand the frozen plan off to a cheap
external runtime (Codex `gpt-5.6-luna`, Gemini Flash, second Claude session) — **with
the user choosing via a question that shows options, a computed recommendation, and
what each option costs and gets.** Plus: copy the brainstorming right-sizing
(Spike/Bounded/Architectural + mid-task upgrade) from obra/superpowers.

## Design

### Per-task execution class (precision lever)

Phase 3 tags every plan task with `Exec class`: `mechanical` | `logic` | `ui` | `qa`.
Classification errs UP; only `mechanical` may run on a cheap model. `qa` always routes
to `qa-automation`. An under-specified task that lands on `logic` is a planning smell —
specify it down to `mechanical` or accept the cost.

### Interactive routing picker (Phase 3, step 6c)

A dedicated `AskUserQuestion` option-set, folded into the existing run-controls picker,
with a **computed recommendation pre-selected** and per-option explanation (models used,
rough cost band from `patterns/cost.yaml` `routes × models × routing_bands` and the
task-class mix, quality/risk trade):

| Preset | mechanical | logic / ui | Cost band | When recommended |
|---|---|---|---|---|
| **Balanced** | sonnet | sonnet | ≈ 1× | high-risk / Tier L / logic-heavy / default |
| **Economy** | **haiku** | sonnet | ≈ 0.3–0.6× | Tier S/M, mechanical-heavy (≥60%), low risk |
| **Max quality** | sonnet | **opus** | ≈ 2–4× | security-critical / Tier L |
| **Hand-off** | — (external) | — (external) | ≈ 0× this session | lowest cost / async / other runtime |

Recommendation logic: risk overlap with `gate.yaml` denylist, autonomy tier, and the
logic-vs-mechanical mix → pre-selected preset + one-line reason.

### Persistence & non-interactive

`customize.toml` `[executor].routing` (`ask` default) pins a preset and skips the
question (autonomous/CI silence); `[executor.by_class]` overrides the per-class map.
After an interactive answer, offer once to save it to the repo `customize.toml`.

### Hand-off

If Hand-off is chosen: finalize the plan, do NOT arm `.active-plan`, STOP after Phase 3,
print the plan path + resume command per runtime (`/hydraia:resume` for Claude,
`bash codex/setup.sh` + `$hydraia` for Codex). The plan is already a portable,
self-contained hand-off (plancheck enforces self-containment), so external cheap
execution is safe.

### Phase 4 application

Map each task's `Exec class` → model via the active preset (or `[executor.by_class]`),
dispatch `hydraia-executor` with that model. Cheap-model failures are caught by the
existing watchdog + circuit breaker and re-dispatched; never silently upgrade a model
mid-run without logging it.

### Brainstorming right-sizing (copied, adapted)

Add Spike / Bounded / Architectural classification + mid-task path upgrade to
`skills/brainstorming/SKILL.md`. Adaptation vs superpowers: hydraia ALWAYS writes a
spec (the spec-drive gate needs it) — the class decides its length, not its existence.
Bounded collapses the 2–3-approach survey and section-by-section approval into one short
in-chat design + a minimal spec; Spike is a probe plan + finding; Architectural is the
full flow.

## Files touched (increment 2)

- `skills/hydraia/phases/phase-3-plan.md` — `Exec class` in task format; routing picker (6c).
- `skills/hydraia/phases/phase-4-execute.md` — per-class routing table + application.
- `skills/hydraia/customize.toml` — `[executor].routing` + `[executor.by_class]`.
- `patterns/cost.yaml` — `models` weights + `routing_bands`.
- `skills/hydraia/SKILL.md` + `codex/skills/hydraia/SKILL.md` — routing fact in dispatcher.
- `skills/brainstorming/SKILL.md` — Spike/Bounded/Architectural + mid-task upgrade.
- `codex/skills/hydraia/phases/*` — re-mirrored byte-identical.
- `CHANGELOG.md` — increment-2 entries.

## Success criteria (increment 2)

- Phase 3 asks the routing question with a pre-selected recommendation + per-option cost/gets.
- A plan task's `Exec class` drives the Phase-4 model per the chosen preset.
- `[executor].routing = "economy"` runs non-interactively with Haiku on mechanical tasks.
- Hand-off stops after Phase 3 with a runnable resume command; nothing executes locally.
- Security floor runs regardless of routing.
- brainstorming right-sizes by class but always yields a spec + approval.
