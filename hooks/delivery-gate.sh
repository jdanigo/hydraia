#!/usr/bin/env bash
# Hydraia delivery-gate (Stop hook). ECC-inspired. Deterministic — no AI, zero tokens.
#
# Scans the session transcript tail for rationalization patterns ("skip tests for now",
# "pre-existing bug", "good enough", "will fix later", "disable the lint/type rule") and
# WARNS (never blocks — avoids false positives). Also flags an incomplete sprint-status
# (an Agile run that stopped mid-epic). Warn-only: always exits 0.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true

payload="$(cat 2>/dev/null || true)"
MODE="on"; command -v hy_config >/dev/null 2>&1 && MODE="$(hy_config deliveryGate on HYDRAIA_DELIVERY_GATE)"
[ "$MODE" = "off" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

tpath="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    print((json.load(sys.stdin) or {}).get("transcript_path") or "")
except Exception:
    print("")
' 2>/dev/null || true)"

if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  hits="$(tail -c 200000 "$tpath" 2>/dev/null | tr 'A-Z' 'a-z' | grep -oE \
    'skip(ping)? (the )?tests? for now|pre-existing bug|good enough for now|will fix (this )?later|disable the (lint|type|eslint|ruff) rule|ignore the (test|type) (error|failure)' \
    2>/dev/null | sort -u | head -5 || true)"
  if [ -n "$hits" ]; then
    {
      echo "[hydraia] delivery-gate — rationalization patterns detected in this session:"
      printf '  • %s\n' $hits 2>/dev/null || echo "  • (see transcript)"
      echo "These often precede shipped defects. Confirm tests actually run and nothing was waved through."
    } >&2
  fi
fi

# Incomplete Agile epic warning (best-effort).
repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$repo" ]; then
  adir="$(cd "$repo" 2>/dev/null && hy_artifacts_dir 2>/dev/null)"; [ -n "$adir" ] || adir="$repo/docs/hydraia"
  for ss in "$adir"/epics/*/sprint-status.yaml; do
    [ -f "$ss" ] || continue
    if grep -qE 'phase: (spec|plan|build|review|verify)\b' "$ss" 2>/dev/null; then
      echo "[hydraia] delivery-gate — an Agile epic looks mid-flight ($ss). Resume with /hydraia:resume." >&2
    fi
  done
fi
exit 0
