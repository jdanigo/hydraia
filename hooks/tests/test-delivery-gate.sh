#!/usr/bin/env bash
# Fixtures for delivery-gate.sh — always exit 0 (warn-only); warns on rationalization.
set -uo pipefail
H="$(cd "$(dirname "$0")/.." && pwd)/delivery-gate.sh"
pass=0; fail=0
tmp="$(mktemp)"; printf 'I will just skip the tests for now, good enough for now.\n' > "$tmp"
out="$(printf '{"transcript_path":"%s"}' "$tmp" | bash "$H" 2>&1)"; ec=$?
[ "$ec" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL exit want 0 got $ec"; }
echo "$out" | grep -qi "rationalization" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL no warning emitted"; }
printf '{}' | bash "$H" >/dev/null 2>&1; [ "$?" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL empty payload"; }
rm -f "$tmp"
echo "delivery-gate: $pass passed, $fail failed"; [ "$fail" = 0 ]
