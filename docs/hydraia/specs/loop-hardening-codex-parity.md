# Loop-Hardening — Codex Parity Checklist

The Claude side of loop-hardening (spec `2026-08-19-loop-hardening-design.md`) is
implemented in `hooks/` + `skills/hydraia/SKILL.md`. The Codex port must mirror it under
`codex/`. Data files are SHARED (read as-is); only the hook LOGIC is duplicated.

## Shared data (read directly, do NOT duplicate)
- [ ] `gate.yaml` — blastgate denylist/maxFiles.
- [ ] `docs/hydraia/constraints.md` (or `$hbase/constraints.md`) — binding constraints.
- [ ] `$hbase/.agents/ledger.json` — breaker attempt counts.
- [ ] `patterns/cost.yaml` — cost anchors.
- [ ] `loop-budget.md` — human budget doc.
- [ ] New config keys in `~/.config/hydraia/config.json` (Codex `config.sh` uses the same `hy_config` contract).

## Duplicated logic (new Codex files, same behavior, Codex hook I/O schema)
- [ ] `codex/hooks/blastgate.sh` — port `hooks/blastgate.sh`; read Codex payload (apply_patch args + shell write path), same gate.yaml, same block contract (exit 2 + JSON).
- [ ] Breaker in the Codex agents-budget hook — port the ledger block from `hooks/agents.sh`; resolve slug from the Codex executor spawn args (`[task:<slug>]` tag carried in the agent prompt).
- [ ] Token caps + kill switch in the Codex agents-budget hook — same telemetry read (`~/.cache/hydraia/telemetry.jsonl`), same `loopPause`/`HYDRAIA_PAUSE`.
- [ ] Constraints injection in `codex/hooks/preflight.sh` — same file, Codex additionalContext mechanism.
- [ ] `codex/setup.sh` — install `blastgate.sh` into `~/.codex` and wire it in `~/.codex/hooks.json` alongside the gate.

## Shared PIPELINE CONTRACT (keep byte-identical, CI drift check)
- [ ] Phase -1 tier + cost + noop block.
- [ ] Phase 0 "Binding constraints (read first)" paragraph.
- [ ] Phase 4 `[task:<slug>]` tag + breaker escalation.
- [ ] Phase 5 `maxReviewCycles` re-review cap.
Copy these blocks verbatim from `skills/hydraia/SKILL.md` into `codex/skills/hydraia/SKILL.md`.

## Config keys the Codex `config.sh` must recognize
`pathGate`, `maxFilesEnforce`, `constraintsInject`, `maxReviewCycles`, `dailyTokenCap`, `perRunTokenCap`, `loopPause`, `autoTier` (+ env homologs). All via the existing `hy_config` contract — no schema change, just honored by the Codex hooks.
