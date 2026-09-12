#!/usr/bin/env bash
# Fixtures for gateguard.sh — deterministic: pin HYDRAIA_DOCS_DIR to a temp base
# (same technique run.sh uses) so hook + fixture agree regardless of outer env.
set -uo pipefail
H="$(cd "$(dirname "$0")/.." && pwd)/gateguard.sh"
pass=0; fail=0
tmp="$(mktemp -d)"; ( cd "$tmp" && git init -q && git commit -q --allow-empty -m init 2>/dev/null || true )
base="$tmp/docs/hydraia"; mkdir -p "$base/.agents"
P='{"tool_name":"Write","tool_input":{"file_path":"x.py"}}'
run(){ ( cd "$tmp" && printf '%s' "$P" | env -u HYDRAIA_ALLOW_DIRECT HYDRAIA_DOCS_DIR="$base" HYDRAIA_GATE_GUARD="$1" bash "$H" >/dev/null 2>&1 ); ec=$?; \
  if [ "$ec" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL[$3] want $2 got $ec"; fi; }

printf 'x\n' > "$base/.active-plan"
run "off" 0 "off-allows"
run "on"  2 "on-no-facts-blocks"
rid="$(stat -f %m "$base/.active-plan" 2>/dev/null || stat -c %Y "$base/.active-plan" 2>/dev/null || echo 0)"
printf 'facts\n' > "$base/.agents/facts-$rid"
run "on"  0 "on-with-facts-allows"
rm -rf "$tmp"
echo "gateguard: $pass passed, $fail failed"; [ "$fail" = 0 ]
