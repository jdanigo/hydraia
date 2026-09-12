#!/usr/bin/env bash
# Hydraia gateguard (PreToolUse on Edit|Write|Bash). ECC-inspired. OPT-IN (default off).
#
# Forces the agent to record concrete facts before its FIRST write of a run — the files
# that import the target, the schema/fields touched, and the verbatim task instruction —
# so autonomous execution investigates instead of guessing. When gateGuard=on and no facts
# file exists for the run, the first write is blocked (exit 2) with instructions; once the
# facts file is written, writes proceed. Loop-safe: only the first write is gated per run.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true

command -v python3 >/dev/null 2>&1 || exit 0
cat >/dev/null 2>&1 || true   # drain stdin; decision does not need the payload body
[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0

repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0
adir="$(cd "$repo" 2>/dev/null && hy_artifacts_dir 2>/dev/null)"; [ -n "$adir" ] || adir="$repo/docs/hydraia"

MODE="off"; command -v hy_config >/dev/null 2>&1 && MODE="$(hy_config gateGuard off HYDRAIA_GATE_GUARD)"
[ "$MODE" = "on" ] || exit 0

plan="$adir/.active-plan"
[ -f "$plan" ] || exit 0                 # only meaningful inside an armed run
adir_agents="$adir/.agents"; mkdir -p "$adir_agents" 2>/dev/null || exit 0
runid="$(stat -f %m "$plan" 2>/dev/null || stat -c %Y "$plan" 2>/dev/null || echo 0)"
facts="$adir_agents/facts-$runid"

[ -f "$facts" ] && exit 0                 # facts recorded → allow

cat >&2 <<EOF
[hydraia] BLOCKED: gateguard — record facts before the first write of this run.

Investigate, don't guess. Write "$facts" containing, for the change you are about to make:
  • the files that import / call the symbol you are editing (grep the codebase),
  • the schema / field names / data shapes you will touch,
  • the verbatim task or instruction you are implementing.

Then retry the write. This gate fires once per run. Disable with gateGuard=off.
EOF
exit 2
