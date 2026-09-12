## Phase 2a — Epic decomposition (Agile Mode only)

Reached only when `mode = agile`. This replaces the single-goal Phase 2 with epic-level
design + a decomposition into an executable story tree. It is the **one heavy,
human-approved design step** of an Agile run — the thinking happens here, once; stories
run light afterward.

Artifacts base is the resolved `<base>` (in-repo `docs/hydraia/` or the external dir).
Derive an `<epic-slug>` from the intent; everything lives under `<base>/epics/<epic-slug>/`.

### 1. Epic-level design (heavy, once)

Run the normal Phase 2 design **at epic scope** — use **brainstorming** for the shape,
then write `<base>/epics/<epic-slug>/epic.md` with: the epic goal, the architecture spec,
and a **threat model** for the whole epic (the per-story runs inherit this; they do NOT
each re-do a threat model unless a story is tier-L). If the epic has any UI, the
**ui-ux-pro-max** visual system is decided here, once, and carried into UI stories — same
hard gate as Phase 2.

### 2. Decompose into a story tree

Adopt the decomposition discipline (from BMAD `create-epics-and-stories`) as the standard:

- **Stories are independently completable, in dependency order.** **No forward
  dependencies within the epic** — story N may depend only on stories before it, never a
  later one. A story that needs a not-yet-built thing means the order is wrong; fix the order.
- **Create only what the story needs.** Never one story that builds all the schema/entities
  up front — each story creates/alters only the tables and interfaces it uses.
- **Single dev-agent sized.** Each story is a coherent unit one executor can complete;
  split anything larger, consolidate anything trivial. A story is NOT a micro-edit.
- **Acceptance in Given/When/Then**, and a **QA plan per story**.
- Break each story into **Tasks** and, where useful, **Subtasks** — these become the
  Phase-4 executor units, each carrying an `Exec class` (mechanical/logic/ui/qa) at
  orchestration time.

Compute each story's **autonomy tier** (S/M/L) from its likely files, `gate.yaml` overlap,
new-logic-vs-mechanical, and UI presence — the same signals Phase -1 uses. Record it; the
orchestrator re-checks it before running the story.

### 3. Write the tree

Write, under `<base>/epics/<epic-slug>/`:
- `stories.yaml` and `sprint-status.yaml` (schemas in `phases/agile-artifacts.md`) — one
  entry per story with `id`, `title`, `deps`, `tier`, `routing` (empty = inherit the epic
  default), `jira_key` (empty), `status: todo`.
- `stories/<id>-<slug>.md` — the story goal + Given/When/Then acceptance (the story-scoped
  mini-spec is filled by the orchestrator at run time from the epic context).
- `qa/<id>-cases.md` — the QA case doc per story.

### 4. Epic-context distillation

Follow `phases/epic-context.md` to write `<base>/epics/<epic-slug>/epic-context.md` — the
distilled context (800–1500 tokens) every story loads instead of the raw epic.md/planning
docs. This is what keeps running N stories economical.

### 5. Execution routing default

Present the routing presets (Balanced/Economy/Max-quality, from the Phase-3 picker) at
**epic level** and record the choice as `[agile.routing].default` for this run (or read it
from `customize.toml`). Per-story overrides live in `stories.yaml` `routing`. This is the
epic-level tier of the multi-level model resolution.

### 6. Jira offer

If the Jira MCP is available, follow `phases/jira-sync.md` to offer pushing the whole tree
now (Epic→Story→Task→Subtask+QA) and record the returned keys in `stories.yaml`. Absent or
declined → stay local; the run is identical.

### CHECKPOINT (the one heavy approval)

Present the epic design + the story map (ids, titles, deps, tiers, routing) and **HALT for
human approval** before any execution. Nothing runs until the human approves the
decomposition. On approval, arm the run (`.active-plan`) and record `mode: agile` + the
epic path in the run log.

## NEXT

Read fully and follow `phases/agile-orchestrator.md`.
