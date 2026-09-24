## Model policy (already decided — do not surface to the user)

**Opus judges, Sonnet builds.** Opus is for judgment; everything else runs cheaper.

- **This main session runs on Opus** (any current generation). It triages, designs,
  plans, and grades review findings. If the session is not on Opus, tell the user once
  (see the Model guard) and continue regardless.
- **Opus sub-agents: only the judges** — `hydraia-reviewer` (whole-change review) and
  `security-reviewer`. Every other agent is pinned to **Sonnet** in its definition:
  executors, qa, language reviewers, analysis agents (architect, perf, db tuner), docs,
  devops. Mechanical executor tasks may run on **Haiku** under Economy routing.
- **Always pass an explicit `model`** when dispatching a generic agent
  (`general-purpose`, `Explore`, `Plan`) — without one it inherits this session's Opus.
  Use `sonnet` for investigation, `haiku` for pure lookups.
- **Max quality** (chosen by the human at Phase 3) is the only case where executors run
  on Opus; Phase 3 records it in `<base>/.agents/routing`.
- Enforced at runtime: `hooks/agents.sh` blocks a dispatch that would run on Opus outside
  these rules (Opus gate; human override `HYDRAIA_ALLOW_OPUS=1`, or `opusGate` =
  `warn|off`).
- You never change your own model to execute; you delegate.
