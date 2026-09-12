## Agile orchestrator — sequential per-story execution (Agile Mode)

Reached from `phase-2a-decompose.md` after the human approves the story tree. Drives each
story to done, in dependency order, reusing the existing pipeline phases per story. This
file **orchestrates**; it does not re-specify execution/review/verify — it points to the
existing phase files for each per-story run.

State lives in `<base>/epics/<epic-slug>/{stories.yaml,sprint-status.yaml}` (schemas in
`phases/agile-artifacts.md`). Checkpoint after every phase so the run is resumable.

### The loop

Compute the topological order over `stories.yaml` `deps` (refuse a cycle or a forward
edge — report, don't run). Then, for each story in order:

1. **Tier gate (autonomy decision).** Re-check the story's tier (files it will touch,
   `gate.yaml` denylist overlap, new-logic-vs-mechanical, UI). Run autonomously when it is
   Tier S/M and clean. **PAUSE for human approval before running** when it is **Tier L**,
   overlaps a denylist path (auth/payments/migrations/secrets), or is irreversible. This is
   the whole point of "autonomy by tier": mechanical stories flow, risky ones stop.

2. **Resolve model routing** (multi-level, most specific first): each task's `Exec class`
   → the story's `routing` → `stories.yaml` `routing_default` (the epic default) →
   `customize.toml` `[executor]`/`[agile.routing]` → global. Opus stays reserved for
   judgment (this orchestration, review triage, tier gating); Sonnet/Haiku execute.

3. **Run the per-story pipeline** (light by default; tier-L escalates):
   - Load `<base>/epics/<epic-slug>/epic-context.md` + the story file. Do NOT load the raw
     epic.md/planning docs — the distilled context is the point.
   - **Mini-spec:** write the story-scoped spec into `stories/<id>-<slug>.md` — acceptance
     (Given/When/Then) + a Code Map for this story, derived from the epic context. **No new
     threat model** unless the story is tier-L (it inherits the epic threat model).
   - **Plan:** `phases/phase-3-plan.md` scoped to this story — tasks carry `Exec class`,
     literal inlined content, self-contained (plancheck applies).
   - **Build:** `phases/phase-4-execute.md` — dispatch executors per the resolved routing,
     bounded waves, watchdog, all as today.
   - **Review:** `phases/phase-5-review.md` — **depth by tier**: tier-L gets the full
     double review + its own threat-model pass; S/M get the lite path. The **security floor
     always runs** (security-scan + security-review + high-severity blocks) regardless of
     tier — the tier never removes it. Claim-verify + gamed-verification hunt apply.
   - **Verify:** `phases/phase-6-verify.md` — mechanical-first, real build/tests, named
     regression test per bug fixed. QA/E2E per the story's plan.

4. **Sync Jira** at each phase edge via `phases/jira-sync.md`: transition the story's issue
   `todo → in-progress → in-review → done` and comment with the spec/plan/PR link. One-way;
   a failure warns and continues.

5. **Checkpoint.** Update `sprint-status.yaml` (`current`, the story's `phase`) and
   `stories.yaml` (`status`) after each phase; commit per the auto-commit choice. The
   circuit breaker (`hooks/agents.sh`) counts this story's task attempts as usual.

6. **Next story.** On a genuine blocker — breaker cap hit, a verify failure that can't be
   fixed, a tier-L story the human rejects — mark the story `blocked`, HALT with the story
   id + evidence, and stop. The rest of the epic stays resumable via `/hydraia:resume`.

### Close the epic

When every story is `done`: run a final epic-level pass — `repo-scan` + `production-audit`
over the whole epic branch (the close-time security gate), emit the run summary (per the
summary-depth choice), disarm the gate (`rm -f .active-plan`), and print the credits line.

## NEXT

End of the Agile run. `/hydraia:resume` re-enters here from `sprint-status.yaml` if the run
was interrupted. Reference files (`epic-context.md`, `agile-artifacts.md`, `jira-sync.md`)
are loaded on demand, not sequential steps.
