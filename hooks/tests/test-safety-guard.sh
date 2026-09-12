#!/usr/bin/env bash
# Fixtures for safety-guard.sh — block destructive, allow benign, fail-open.
set -uo pipefail
H="$(cd "$(dirname "$0")/.." && pwd)/safety-guard.sh"
pass=0; fail=0
run(){ printf '%s' "$2" | env -u HYDRAIA_ALLOW_DIRECT bash "$H" >/dev/null 2>&1; ec=$?; \
  if [ "$ec" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL[$3] want $1 got $ec"; fi; }
J(){ printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
run 2 "$(J 'rm -rf /')"                 "rm-rf-root"
run 2 "$(J 'git push --force origin main')" "force-push"
run 2 "$(J 'psql -c \"DROP TABLE users\"')" "drop-table"
run 0 "$(J 'npm test')"                 "benign-test"
run 0 "$(J 'ls -la')"                   "benign-ls"
run 0 'not json'                        "fail-open-bad-json"
echo "safety-guard: $pass passed, $fail failed"; [ "$fail" = 0 ]
