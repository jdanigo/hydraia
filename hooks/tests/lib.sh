#!/usr/bin/env bash
# Minimal assert helpers for hydraia hook tests. A hook reads its JSON payload on stdin
# and signals via exit code (0 allow, 2 block). These run the hook with a payload + env
# and assert the result. No framework — portable bash.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

# assert_exit <expected-code> <hook-name> <payload-json> [ENV=val ...]
assert_exit() {
  local want="$1" hook="$2" payload="$3"; shift 3
  local out code
  out="$(printf '%s' "$payload" | env "$@" "$HOOKS_DIR/$hook" 2>/dev/null)"; code=$?
  if [ "$code" = "$want" ]; then PASS=$((PASS+1)); printf '  ok   %s exit=%s\n' "$hook" "$code"
  else FAIL=$((FAIL+1)); printf '  FAIL %s want=%s got=%s\n' "$hook" "$want" "$code"; fi
}

# assert_stderr <substring> <hook-name> <payload-json> [ENV=val ...]
assert_stderr() {
  local want="$1" hook="$2" payload="$3"; shift 3
  local err
  err="$(printf '%s' "$payload" | env "$@" "$HOOKS_DIR/$hook" 2>&1 >/dev/null)"
  if printf '%s' "$err" | grep -qF "$want"; then PASS=$((PASS+1)); printf '  ok   %s stderr~%s\n' "$hook" "$want"
  else FAIL=$((FAIL+1)); printf '  FAIL %s missing stderr %s\n' "$hook" "$want"; fi
}

report() { printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"; [ "$FAIL" = 0 ]; }
