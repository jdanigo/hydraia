# Hydraia Constraints — <repo>

> Copy this file to `constraints.md` (same dir) to activate. It is read at the start of
> every session (injected as binding context by hooks/preflight.sh) and again in Phase 0.
> Rules here are BINDING — the agent must follow them. Keep it short (< 8 KB).

## Push & Merge
- Don't push before telling me.
- Never merge to main without human approval.

## Paths
- Never edit `.env`, `auth/`, `payments/`, `secrets/`, `credentials/` (also enforced by gate.yaml).
- Name any module the agent must not touch here.

## Code
- Run the project's tests before proposing a fix.
- Never disable a test to make CI green.
- One focused change per run — no unrelated refactors.

## Communication
- Say what you're about to do before doing it.
- Never close an issue or PR without approval.

## Budget
- If token spend hits the daily cap, switch to report-only.
- If HYDRAIA_PAUSE is set, exit immediately.
