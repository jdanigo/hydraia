## Phase -1 — Intent triage (before everything)

Classify the request into exactly ONE route before any other guard runs.
Explicit commands skip classification and force their route
(`/hydraia:feature` → feature · `/hydraia:story` → user story ·
`/hydraia:plan` → feature, stopping after Phase 3 · `/hydraia:review` →
review · `/hydraia:perf` → performance · `/hydraia:db` → performance,
DB-shaped · `/hydraia:architect` → greenfield · `/hydraia:e2e` → E2E suite ·
`/hydraia:devops` → DevOps config · `/hydraia:observability` → instrumentation ·
`/hydraia:docs` → docs sync · `/hydraia:agile` → any route with **mode = agile**
forced). Plain-language requests are classified by signals:

| Intent | Signals | Route |
|---|---|---|
| Feature / change | "add / build / implement / change X" | Phases 0–6 as written below |
| User story | "As a … I want … so that …", acceptance-criteria lists, ticket text or a Jira/PDF export | Run the **story-analysis** skill FIRST (interactive PO pass → story artifact with numbered ACs), then Phases 0–3 with that artifact as the primary design input; continue into 4–6 only when the entry point runs the full pipeline |
| Bug / unexpected behavior | "fails / broken / error / regression / used to work" | **systematic-debugging** skill first — root cause before any fix. Enter the pipeline only if the fix requires new design/behavior; a surgical fix proceeds under that skill's rules (the spec-drive gate still applies) |
| Performance / DB symptom | "slow / timeout / high CPU / memory climbing / query takes …" | Run the **performance-tuning** skill flow: measured baseline FIRST, dispatch `perf-engineer` (and `db-performance-tuner` when the symptom is DB-shaped, per **db-optimization**), spec carries baseline + numeric target, Phase 6 re-measures against it |
| New app / greenfield | "from scratch / new app / new service / greenfield" | Run the **greenfield-architect** skill: elicitation → architecture proposals (`architect` + `code-architect`, microservices only with evidence) → confirmed stack → **api-design** contract when an API exists → **adr** records per decision — then Phases 0–6 |
| Review / audit | "review / audit this branch / this PR" | Phases 5–6 only |
| Ambiguous | none of the above clearly | `AskUserQuestion` listing the plausible routes — never assume |

Triage is ONE classification step, not a conversation — at most a single
routing question, and only when genuinely ambiguous. Route chosen, proceed
to the work-mode selection, then the guards below.

### Work mode (after route, before the tier)

The **mode** is a layer over the route — it decides how much decomposition and
orchestration the run gets, not what kind of work it is. Ask once, via a single
`AskUserQuestion`, with a computed recommendation pre-selected:

- **Quick** — one small, low-risk change (no new logic, ≤ ~2 files). Minimal ceremony
  (the `.quick-approved` path). Recommend for trivial mechanical intent.
- **Plan** — one cohesive goal, the full single-goal pipeline (today's default). Recommend
  for a normal feature/bug/change.
- **Agile** — epic-sized work, **multiple independent shippable goals**, or delivery the
  user wants run in phases/stages. Decompose into Epic → Stories → Tasks → Subtasks + QA,
  optionally sync to Jira, then execute stage by stage under tiered autonomy. Recommend
  when ≥2 independent goals are detected, the intent is epic-sized, or the user says "by
  phases / in stages / step by step".

Skip the ask when forced: `/hydraia:agile` → Agile; `customize.toml` `[agile].mode` set to
a concrete value → that mode; an already-`.quick-approved` trivial change → Quick.

- **If mode = Agile:** run the guards + Phase 0/1 as usual, then **branch to
  `phases/phase-2a-decompose.md`** instead of `phases/phase-2-design.md`. Everything from
  decomposition onward is Agile Mode.
- **If mode = Quick or Plan:** continue exactly as today (Plan = full pipeline, Quick =
  trimmed). No Agile phases run.

**Multi-goal is the Agile trigger.** Wherever the pipeline detects multiple independent
shippable goals (the multi-goal check that today splits to `deferred-work.md`), offer
"carry all goals as one epic in Agile Mode" as an alternative to splitting — that is the
intended home for multi-goal work, not deferral.

### Autonomy tier + cost (after route, before the guards)

Once the route is chosen, estimate a **tier** from cheap signals and show a cost
estimate. This maps to hydraia's EXISTING controls — it adds no new enforcement axis.

**Early-exit (noop) first.** If the route's target is empty, do not spin the pipeline:
- `review` / `graph`: if `git diff --name-only` against the branch point is empty (or the
  named target does not exist), report "nothing to review", drop the run-complete marker
  (`printf 'brief\n' > <base>/.run-complete`), and stop. No Phases 0–6.
- `perf` / `db`: if the named symptom target is absent or already within a stated
  threshold, report and stop.

**Tier (feature-shaped routes).** Classify from: likely files touched, overlap with the
`gate.yaml` denylist (risk), new-logic vs mechanical, presence of UI surfaces:
- **Tier S (trivial):** no new logic, no new file, no risk-path, ≤ ~2 files → propose
  quick-mode (the `.quick-approved` path) or a Lite review. Minimal ceremony.
- **Tier M (standard):** default — full pipeline, Full review.
- **Tier L (large / risky):** many files, risk-path overlap, or a new service → full
  pipeline + all gates; the human may raise the agent ceiling.

**Cost estimate.** Read `patterns/cost.yaml` for the route × tier and state a one-line
token estimate (e.g. "≈200k tokens, Tier S"). It is a rough anchor, not a promise.

**Confirm once.** Present the tier + estimate in a single `AskUserQuestion`,
pre-selecting the review depth for the Phase-3 run-controls picker. The human confirms
with one tap or overrides. Honor `autoTier` config (`off` → always Tier M, today's
behavior). A tier NEVER removes the security floor (Phase 5 mandatory reviewers, threat
model) — Tier S only trims optional ceremony, exactly as quick-mode already does.



## NEXT

Read fully and follow `phases/guards.md`.
