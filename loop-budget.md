# Loop Budget — Hydraia

Human-readable companion to the token-cap config keys (enforced by hooks/agents.sh).

## Caps (config keys, default 0 = off)
| Key | Meaning |
|-----|---------|
| `dailyTokenCap` | Max in+out tokens (all runs) per rolling 24h before new sub-agent dispatch is blocked. |
| `perRunTokenCap` | Same, scoped to the current run. |
| `loopPause` / `HYDRAIA_PAUSE` | Kill switch — blocks all sub-agent dispatch immediately. |

Token caps act on **completed-run** telemetry: `summary.sh` writes spend only at run close, so the caps throttle the NEXT sub-agent dispatch based on recent spend — they do not halt the current run mid-flight. `perRunTokenCap` therefore bites once the in-flight run's own telemetry has been recorded (i.e. on a subsequent run of the same plan), and `dailyTokenCap` throttles once the rolling-24h total of closed runs crosses the ceiling.

## On cap exceed
1. Hooks block new Task dispatch; the orchestrator switches to report-only and surfaces the blocker.
2. Raise the cap (`export HYDRAIA_DAILY_TOKEN_CAP=…`) or clear the pause to resume — the human's call.

## Estimate
Phase -1 prints a per-route estimate from `patterns/cost.yaml`. Edit that file to retune anchors.

## Convergence breakers (v0.22, on by default)
| Key / env | Default | Meaning |
|-----|---------|---------|
| `maxSameFailure` / `HYDRAIA_MAX_SAME_FAILURE` | 3 | Same failure signature N× in a run → STALLED: verify commands blocked (NO PROGRESS warning at 2×). `hooks/verifyloop.sh` |
| `verifyPattern` / `HYDRAIA_VERIFY_PATTERN` | built-in | Regex for what counts as a verify command (tests/builds/lints). |
| `maxFixAttempts` / `HYDRAIA_MAX_FIX_ATTEMPTS` | 2 | `[fix:<slug>]` dispatches per finding. `hooks/agents.sh` |
| `maxFixDispatches` / `HYDRAIA_MAX_FIX_DISPATCHES` | 6 | Total fix dispatches per run. |
| `maxReviewCycles` / `HYDRAIA_MAX_REVIEW_CYCLES` | 2 | Judge (`hydraia-reviewer`) passes per run. |
| `opusGate` / `HYDRAIA_OPUS_GATE` | strict | Opus only for judges (+ executors under Max quality). `warn` / `off`. Bypass `HYDRAIA_ALLOW_OPUS=1`. |
| `scopeGate` / `HYDRAIA_SCOPE_GATE` | strict | Edits outside the frozen plan's `**Files:**` blocked. `warn` / `off`. `hooks/blastgate.sh` |
| `planContract` / `HYDRAIA_PLAN_CONTRACT` | strict | Every task needs `**Files:**` + a Verify line to arm. `hooks/plancheck.sh` |
| `HYDRAIA_BASELINE_TIMEOUT` | 600 s | Hard timeout for the Phase-0 baseline run (`hooks/baseline.sh`). |

Also always on: a verify command sent to the background without `timeout`/`gtimeout` is
blocked. Clear a STALLED run (human only): `rm <base>/.agents/verify.json`.
`HYDRAIA_ALLOW_DIRECT=1` lifts every gate.
