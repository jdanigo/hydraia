## Agile Mode artifacts & state (reference)

The state files under `<base>/epics/<epic-slug>/` that the decomposer writes, the
orchestrator advances, resume reads, and the Jira adapter mirrors. Local state is the
source of truth. Reference only — no `## NEXT`.

### `stories.yaml`

```yaml
epic: <epic-slug>
routing_default: balanced   # epic-level routing (balanced|economy|max-quality); [agile.routing].default
stories:
  - id: "1-1"               # <epic>-<n>, stable; never renumbered
    title: "User can request a password reset"
    deps: []                # ids that MUST finish first — never a later id (no forward deps)
    tier: "S"               # S|M|L, computed at decompose, re-checked before run
    routing: ""             # ""=inherit routing_default; else balanced|economy|max-quality
    jira_key: ""            # filled when synced (e.g. PROJ-123)
    status: "todo"          # todo|in-progress|in-review|done|blocked
    tasks:                  # optional at decompose; the plan refines them
      - id: "1-1-t1"
        title: "..."
        exec_class: "mechanical"   # mechanical|logic|ui|qa (drives per-task routing)
```

### `sprint-status.yaml`

```yaml
epic: <epic-slug>
current: "1-1"              # the story in flight (for resume)
development_status:
  "1-1": { phase: "plan", updated: "2026-09-11T10:00:00Z" }
  # phase: decompose-done|spec|plan|build|review|verify|done|blocked
```

### Rules

- **ids are stable.** Never renumber; Jira keys and resume depend on them.
- **`deps` never point forward.** The decomposer guarantees this; the orchestrator runs a
  topological order over `deps` and refuses a cycle or a forward edge (report it, don't run).
- **`status` / `phase` are advanced only by the orchestrator**, checkpointed after each
  phase so `/hydraia:resume` can continue from `current` + its `phase`.
- **Jira mirrors these**, one-way: a local status change triggers a transition; a Jira
  failure warns and never blocks (local stays truth).
