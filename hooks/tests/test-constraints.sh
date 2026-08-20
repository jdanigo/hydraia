#!/usr/bin/env bash
# hooks/tests/test-constraints.sh
REPO="$(git rev-parse --show-toplevel)"
CF="$REPO/docs/hydraia/constraints.md"
printf '# Constraints\n- Never edit auth/\n' > "$CF"
OUT="$(printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$REPO" | CLAUDE_PLUGIN_ROOT="$REPO" bash "$REPO/hooks/preflight.sh" 2>/dev/null || true)"
if printf '%s' "$OUT" | grep -q 'additionalContext' && printf '%s' "$OUT" | grep -q 'Never edit auth'; then
  PASS=$((PASS+1)); echo "  ok   preflight injects constraints"
else PASS=$((PASS)); FAIL=$((FAIL+1)); echo "  FAIL preflight constraints"; fi
rm -f "$CF"
