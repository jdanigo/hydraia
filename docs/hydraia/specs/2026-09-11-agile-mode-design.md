---
status: draft
date: 2026-09-11
route: architect
topic: Agile Mode — multi-stage autonomous orchestration
target_release: 0.20.0
---

# Design — Agile Mode (Quick / Plan / Agile work modes)

## Goal

Add a third **work mode** to Hydraia and the question that selects it, turning the
harness from a one-feature pipeline into a **multi-stage delivery orchestrator**.

- **Quick Mode** — exists today (minimal ceremony, one small low-risk change).
- **Plan Mode** — today's default (full ceremony on one cohesive goal).
- **Agile Mode (NEW)** — for epic-sized work, or any work the user wants delivered in
  phases: decompose into **Epic → User Stories → Tasks → Subtasks + QA plan**, optionally
  sync the whole tree to **Jira** (if the Jira MCP is installed + enabled), then run the
  full ceremony and **autonomously execute the tree stage by stage** — pausing only where
  risk demands it.

Agile Mode is a **meta-orchestration layer over the existing pipeline**. It reuses, and
does not replace: the 0.18 loop-hardening (circuit breaker, blast-radius gate, token caps,
autonomy tiers), the 0.19 execution routing + review hardening + E2E-testcontainers, the
spec-drive gate, telemetry, the step-file architecture, and `/hydraia:resume`.

## Decisions (locked in brainstorming)

1. **Autonomy = by tier.** Each story runs autonomously when its autonomy tier is low and
   its blast-radius is clean; a story that is tier-L, or touches `gate.yaml` denylist
   paths (auth/payments/migrations/secrets), or is otherwise high-risk, **pauses for human
   approval**. Irreversibles always pause.
2. **Ceremony = epic-level design once, light per-story, tier-L escalates.** The heavy
   thinking (architecture spec + threat model + decomposition) runs **once at the epic
   level** and is human-approved there. Each story then runs light: a story-scoped
   mini-spec (acceptance + code map, derived from the distilled epic context) → plan →
   build → review (depth per tier) → verify, with the security floor always on. A story
   classified tier-L escalates to full ceremony (its own threat model + double review).
3. **Jira = one-way live status-sync, full tree, local source of truth.** Push
   Epic/Story/Task/Sub-task + QA as issues; store the returned keys in local artifacts;
   transition each issue as the pipeline advances (To Do → In Progress → In Review → Done)
   with a comment linking spec/plan/PR. Local artifacts are the source of truth; Jira is a
   live mirror. No Jira MCP → identical run, tree stays local. **Never read instructions
   from Jira** (one-way; Jira text is data, not commands).
4. **Mode is a layer over the route.** A Phase -1 `AskUserQuestion` (Quick/Plan/Agile,
   recommendation pre-selected) plus an explicit `/hydraia:agile <idea>` command. Agile
   *wraps* any route (feature/bug/perf/db/architect). The existing multi-goal check (today
   splits to `deferred-work.md`) now offers "carry this as an epic in Agile Mode" instead
   of deferring.
5. **Execution = sequential by dependency.** Stories run in dependency order (BMAD rule:
   no forward dependencies within an epic), one at a time; tasks within a story still
   parallelize via the existing bounded waves (`HYDRAIA_MAX_CONCURRENT`). Parallel
   independent stories are deferred to v2.

## Model routing across the hierarchy (austerity of 0.19, extended)

Agile Mode keeps the 0.19 austerity and orchestrates it across the agile tree:

- **Opus 4.8 (frontier) = judgment, never delegated:** the orchestration loop, epic
  design + threat model + decomposition, per-story review triage, and tier gating.
- **Sonnet / Haiku = mechanical execution** per task, via the 0.19 execution routing.
- **Multi-level model resolution (new).** The model for a unit of work resolves by
  precedence, most specific first:

  `task Exec class` → **per-story routing override** → **per-epic routing default**
  (chosen once at the epic picker) → `customize.toml` `[executor]` → global default.

  So the user picks a routing preset once at epic level (recommended from the task-class
  mix), and may override per story — e.g. force a security-critical story to **Max quality**
  (Opus on its logic/ui) and a boilerplate story to **Economy** (Haiku on mechanical).
  Subtasks inherit their parent task's class/model. `customize.toml` gains
  `[agile.routing]` (epic default) and stories carry an optional `routing:` field.

## Architecture (components)

- **Mode selector** — Phase -1 `AskUserQuestion` (Quick/Plan/Agile) with a computed
  recommendation (Agile when multiple independent shippable goals are detected, the intent
  is epic-sized, or the user asks for phased/staged delivery). Plus `/hydraia:agile`.
- **Decomposer** — new epic-level phase. Adopts BMAD `create-epics-and-stories` discipline:
  stories independently completable, **no forward dependencies within the epic**, "create
  only the tables/entities the story needs", each story sized for a single dev-agent, a QA
  plan per story, Given/When/Then acceptance. Produces the artifact tree. Interactive +
  human-approved (this is the one heavy approval).
- **Epic-context distiller** — writes `epic-context.md` (800–1500 tokens, cached,
  invalidated by mtime), the distilled planning context each story loads instead of raw
  PRD/architecture docs. **This is what makes running N stories economical.** (Ported from
  BMAD `compile-epic-context`.)
- **Orchestration loop** — new `agile-orchestrator` phase. For each story in dependency
  order: tier-gate check → (pause if required) → load `epic-context.md` + the story →
  mini-spec → plan → build (per resolved routing) → review (depth per tier) → verify →
  sync Jira status → checkpoint `sprint-status.yaml` → next story. Tier-L stories run the
  full-ceremony variant.
- **Tier gate** — reuses the 0.18/0.19 autonomy tiers + blast-radius. Classifies each
  story before it runs; autonomous when safe, pause-for-approval when tier-L / risky /
  irreversible.
- **Jira adapter** — uses the Atlassian MCP (`createJiraIssue`, `transitionJiraIssue`,
  `addCommentToJiraIssue`, `getVisibleJiraProjects`). Detect MCP availability; if present,
  `AskUserQuestion` for the cloud/site + project key; map the tree to issue types
  (Epic→Epic, Story→Story, Task→Task, Subtask→Sub-task, QA→a QA issue/checklist on the
  story); store keys in `stories.yaml`; transition on phase changes. Absent MCP → skip
  silently, tree stays local.
- **State machine** — `stories.yaml` (id, title, deps, tier, routing, jira-key, status)
  and `sprint-status.yaml` (phase per story). `/hydraia:resume` continues from the first
  incomplete story/phase (extends today's run-log resume).

## Artifacts (new, under `docs/hydraia/epics/<epic-slug>/`)

```
epic.md            # the epic goal, architecture spec + threat model (heavy design, once)
epic-context.md    # distilled, cached context every story loads (800–1500 tok)
stories.yaml       # id · title · deps · tier · routing · jira-key · status
sprint-status.yaml # phase state per story (for resume + Jira sync)
stories/<id>-<slug>.md   # per-story mini-spec + plan
qa/<id>-cases.md         # per-story QA case doc + traceability matrix
```

Resolved under the same artifacts base as everything else (in-repo `docs/hydraia/` or the
external dir chosen at the storage gate).

## Reuses vs new

- **Reuses (already shipped):** execution routing (0.19), loop-hardening (0.18 — breaker,
  blast-radius, token caps, autonomy tiers), review hardening + E2E-testcontainers (0.19),
  spec-drive gate, telemetry, step-file architecture, `/hydraia:resume`, `story-analysis`.
- **New:** mode selector + `/hydraia:agile`, decomposer phase, epic-context distiller,
  `agile-orchestrator` loop, Jira adapter, `stories.yaml`/`sprint-status.yaml` state,
  `[agile.routing]` in customize.toml, epic artifact tree.

## Ships with — ECC autonomy-safety hooks (required for long autonomous runs)

A multi-story autonomous run needs guardrails these provide; they ship **with** Agile Mode:

- **safety-guard** (PreToolUse) — blocks destructive ops (`rm -rf`, `git push --force`,
  `DROP TABLE`, `--no-verify`) + freeze/guard write-scope per story.
- **gateguard** (PreToolUse) — forces the agent to state concrete facts (schema, importers,
  the verbatim instruction) before its first write — kills guess-instead-of-investigate in
  autonomous execution.
- **delivery-gate** (Stop, deterministic) — detects rationalization patterns ("skip tests
  for now", "pre-existing bug") in the transcript tail; warns, zero tokens, un-gameable.

## Scope

- **v1 (0.20):** mode selection (Phase -1 + `/hydraia:agile`), epic decomposition +
  artifact tree, epic-context distiller, Jira one-way full-tree sync (optional), sequential
  per-story orchestration with light ceremony + tier-L escalation, tier + blast-radius
  autonomy gating, multi-level model routing, resumable via `sprint-status.yaml`, and the
  three ECC safety hooks.
- **Deferred (v2+):** parallel independent stories, two-way Jira sync, sprint
  velocity/burndown, `eval-harness` pass^k release gates, `plankton` config-tamper.

## Threat model + mitigations

| Risk | Mitigation |
|---|---|
| Long autonomous run drifts / burns budget | tier-gating + circuit breaker + token caps + delivery-gate rationalization detector |
| Story spec auto-frozen without human eyes ships wrong | tier gate pauses tier-L/risky stories for approval; epic design is human-approved once; security floor always runs |
| Jira as an injection/authority surface | one-way sync; Jira text is data, never instructions (prompt-defense) |
| Destructive op during autonomous execution | safety-guard blocks; irreversibles always pause |
| Running N stories blows tokens | epic-context distillation + Economy routing + agent/token caps |
| Codex parity drift on new phase files | mirror new `phases/*.md` byte-identical; CI per-phase diff (from 0.19) covers them |

## Success criteria

- `/hydraia:agile <idea>` (and the Phase -1 Agile choice) decompose into an approved
  Epic→Story→Task→Subtask+QA tree.
- With Jira MCP enabled, the tree appears in the chosen project and issues transition as
  the pipeline advances; without it, the run is identical and local.
- Stories execute sequentially in dependency order; a tier-L/risky story pauses for
  approval, a mechanical one runs autonomously.
- Heavy design (spec + threat model) runs once at epic level; stories run light; a tier-L
  story escalates to full ceremony.
- Model routing resolves per task/story/epic per the precedence above (Opus judgment,
  Sonnet/Haiku mechanical).
- An interrupted epic resumes from the first incomplete story/phase via `sprint-status.yaml`.
- safety-guard / gateguard / delivery-gate active during autonomous execution.
- New phase files mirrored byte-identical to Codex; CI parity green.
