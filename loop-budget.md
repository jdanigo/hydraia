# Loop Budget — Hydraia

Human-readable companion to the token-cap config keys (enforced by hooks/agents.sh).

## Caps (config keys, default 0 = off)
| Key | Meaning |
|-----|---------|
| `dailyTokenCap` | Max in+out tokens (all runs) per rolling 24h before new sub-agent dispatch is blocked. |
| `perRunTokenCap` | Same, scoped to the current run. |
| `loopPause` / `HYDRAIA_PAUSE` | Kill switch — blocks all sub-agent dispatch immediately. |

## On cap exceed
1. Hooks block new Task dispatch; the orchestrator switches to report-only and surfaces the blocker.
2. Raise the cap (`export HYDRAIA_DAILY_TOKEN_CAP=…`) or clear the pause to resume — the human's call.

## Estimate
Phase -1 prints a per-route estimate from `patterns/cost.yaml`. Edit that file to retune anchors.
