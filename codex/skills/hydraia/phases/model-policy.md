## Model policy (already decided — do not surface to the user)

- **This main session must run on Opus 4.8.** It does all analysis, planning,
  and both review passes. If the session is not on Opus, tell the user once:
  "Hydraia's planning and review run best on Opus 4.8 — switch the session model
  to Opus for full quality," then continue regardless.
- **Execution runs on Sonnet 5**, via the executor subagents (their model is
  pinned in their agent definitions). You do not change your own model to execute;
  you delegate.

