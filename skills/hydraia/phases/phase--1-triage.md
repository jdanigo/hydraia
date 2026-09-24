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
routing question, and only when genuinely ambiguous. Route chosen, proceed to the
level selection below, then the guards.

### Early exit (noop) first

If the route's target is empty, do not spin the pipeline:
- `review` / `graph`: if `git diff --name-only` against the branch point is empty (or the
  named target does not exist), report "nothing to review", drop the run-complete marker
  (`printf 'brief\n' > <base>/.run-complete`), and stop. No Phases 0–6.
- `perf` / `db`: if the named symptom target is absent or already within a stated
  threshold, report and stop.

### Agile or single goal

**Agile** is for epic-sized work: **≥2 independent shippable goals** (each could be
reviewed, tested and merged as its own PR), or the user asks for delivery "by phases / in
stages". Count deliverables, not verbs — "add validation and show errors" is ONE goal.
Only when ≥2 independent goals are detected, ask once (`AskUserQuestion`): **Agile — one
epic, staged** / **Split — do the first goal now, defer the rest to `deferred-work.md`** /
**Keep as one change**. Otherwise do not ask. Forced by `/hydraia:agile` or
`customize.toml` `[agile].mode`.

- **Agile:** guards + Phase 0/1 as usual, then **branch to `phases/phase-2a-decompose.md`**
  instead of `phases/phase-2-design.md`. Every story then gets its own level (below).
- **Single goal:** pick the level below and continue.

### Level — ONE auto-selected ceremony level (no question)

Ceremony must fit the change. Decide the level from **facts you can state**, not from how
the change feels — a level is a rule outcome, never a shortcut you choose to save tokens.
Write down three facts first (after a quick look at the code graph, not a deep dive):

- **Intent gaps** — what the request does not say, the code cannot settle, and the user
  would notice in the result. (Choices the user would not notice are yours, not gaps.)
- **Irreversibles** — migrations, data deletion/mutation, external side effects,
  deploy/config triggers.
- **Footprint** — files likely touched; new public surface (API, schema, exported type,
  CLI flag); **security surface** (authN/authZ, PII/financial data, untrusted input,
  secrets); overlap with the `gate.yaml` denylist.

| Level | Rule | Ceremony |
|---|---|---|
| **1 — Light** | ALL hold: no intent gaps, nothing irreversible, ≤ 3 files, no new public surface, no security surface, no `gate.yaml` overlap | One-file spec-plan (Intent + Boundaries + a single `## Task 1` with Files + Verify) → one Sonnet executor → Verify → one judge pass (`hydraia-reviewer`) + `security-scan` → close |
| **2 — Standard** | anything that is neither 1 nor 3 (the default when unsure) | Spec → plan-contract → Sonnet executors → judge + security floor, diff-scoped → triage → Phase 6 mechanical gate |
| **3 — Deep** | ANY holds: security surface, `gate.yaml` overlap, irreversible operation, new service/app, > 15 files | Full ceremony: threat model + adversarial design pass, full diff-scoped reviewer panel, QA matrix, E2E gate |

- Security surface or denylist overlap forces **≥ 2** for anything, and **3** for
  feature work touching it — a rule, not a judgment. **The security floor is never
  removed**: Level 1 still gets the judge + `security-scan`.
- Intent gaps do not raise the level by themselves — they are asked in Phase 1/2
  (interactive half), then the level is re-checked.
- **Announce, don't ask.** One line: *"Level 2 — Standard: 6 files, new endpoint, no
  security surface. ≈Xk tokens."* (estimate from `patterns/cost.yaml`: Level 1/2/3 ↔ the
  file's tier S/M/L). The human overrides by saying so at any point; `customize.toml`
  `[pipeline].level` = `1|2|3` pins it; `autoTier` = `off` → always Level 2.
- **Re-level upward, never silently downward.** If Phase 0/2 discovers a trigger for a
  higher level (e.g. the change reaches `auth/`), raise it and say so in one line. Lowering
  a level mid-run is the human's call only.
- The level replaces the old separate questions (Quick-mode offer, tier confirmation,
  review-depth picker). Record it in the run log as `level: <n>`; Phase 3 derives the
  review depth from it (3 → Full, 2 → Lite + diff-scoped language reviewers, 1 → judge-only
  + `security-scan`).

**Level 1 path, concretely.** Guards → Phase 0 (baseline) → Phase 1 → write ONE file,
`<base>/plans/<date>-<slug>.md`: `## Intent` (problem + approach, 2–4 lines),
`## Boundaries` (Always / Never), and a single `## Task 1` with `**Files:**` and
`**Verify:**` → arm `.active-plan` with it (plancheck and the scope gate apply as for any
plan) → dispatch ONE `hydraia-executor` (Sonnet) → Phase 5 judge pass + `security-scan` →
Phase 6 mechanical gate → close. If the executor returns `NEEDS_DECISION` or anything
grows past the Level-1 rule, stop, re-level to 2, and continue with a full spec + plan.

## NEXT

Read fully and follow `phases/guards.md`.
