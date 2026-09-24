# verifyloop.sh — no-progress ledger, stall block, baseline awareness, background guard.
VL_REPO="$(git rev-parse --show-toplevel)"
VL_AD="$HYDRAIA_DOCS_DIR/.agents"; mkdir -p "$VL_AD"
rm -f "$VL_AD/verify.json" "$HYDRAIA_DOCS_DIR/.baseline-failures"
touch "$HYDRAIA_DOCS_DIR/.active-plan"
vl_fail() { # PostToolUseFailure payload for `npm test` with a given error body
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUseFailure","tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"npm test"},"error":sys.argv[2]}))' "$VL_REPO" "$1"
}
E1="$(printf 'Error: Exit code 1\nFAIL src/cart.test.ts > total (31ms)\nAssertionError: expected 10 to be 12')"
E1b="$(printf 'Error: Exit code 1\nFAIL src/cart.test.ts > total (8ms)\nAssertionError: expected 10 to be 12')"
E2="$(printf 'Error: Exit code 1\nFAIL src/tax.test.ts > rate\nAssertionError: expected 0.1 to be 0.2')"
# 1st failure: counted silently. 2nd identical (timing differs): NO PROGRESS. 3rd: STALLED.
assert_exit 0 verifyloop.sh "$(vl_fail "$E1")"
assert_stderr "NO PROGRESS" verifyloop.sh "$(vl_fail "$E1b")"
assert_stderr "STALLED" verifyloop.sh "$(vl_fail "$E1")"
# While stalled: a verify command is blocked at PreToolUse; a non-verify one is not.
VPRE='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$VL_REPO"'","tool_input":{"command":"npx vitest run src/cart.test.ts"}}'
NPRE='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$VL_REPO"'","tool_input":{"command":"git status"}}'
assert_exit 2 verifyloop.sh "$VPRE"
assert_exit 0 verifyloop.sh "$NPRE"
# Bypass lifts the block.
assert_exit 0 verifyloop.sh "$VPRE" HYDRAIA_ALLOW_DIRECT=1
# Fresh ledger: a different failure is counted from 1 (no message).
rm -f "$VL_AD/verify.json"
assert_exit 0 verifyloop.sh "$(vl_fail "$E1")"
assert_exit 0 verifyloop.sh "$(vl_fail "$E2")"
# Pre-existing: failure lines all in the baseline → note, not counted.
rm -f "$VL_AD/verify.json"
printf '# head=x ts=0\n' > "$HYDRAIA_DOCS_DIR/.baseline-failures"
printf '%s' "$E2" | python3 "$HOOKS_DIR/lib/failsig.py" lines >> "$HYDRAIA_DOCS_DIR/.baseline-failures"
assert_stderr "PRE-EXISTING" verifyloop.sh "$(vl_fail "$E2")"
assert_stderr "PRE-EXISTING" verifyloop.sh "$(vl_fail "$E2")"
assert_stderr "PRE-EXISTING" verifyloop.sh "$(vl_fail "$E2")"
rm -f "$HYDRAIA_DOCS_DIR/.baseline-failures"
# Successful PostToolUse (no exit code in tool_response) → allow, not counted.
OK='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$VL_REPO"'","tool_input":{"command":"npm test"},"tool_response":{"stdout":"12 passed","stderr":"","interrupted":false}}'
assert_exit 0 verifyloop.sh "$OK"
# Legacy string tool_response starting with Error counts as a failure.
rm -f "$VL_AD/verify.json"
LEG="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"pytest -q"},"tool_response":sys.argv[2]}))' "$VL_REPO" "$E2")"
assert_exit 0 verifyloop.sh "$LEG"
assert_stderr "NO PROGRESS" verifyloop.sh "$LEG"
# Background guard: verify cmd in background without timeout → block; with timeout → ok.
BG='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$VL_REPO"'","tool_input":{"command":"dotnet test MiPos.Tests","run_in_background":true}}'
BGT='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$VL_REPO"'","tool_input":{"command":"timeout 600 dotnet test MiPos.Tests","run_in_background":true}}'
rm -f "$VL_AD/verify.json"
assert_stderr "background verify" verifyloop.sh "$BG"
assert_exit 0 verifyloop.sh "$BGT"
# No active plan: ledger untouched (failures not counted), background guard still on.
rm -f "$HYDRAIA_DOCS_DIR/.active-plan" "$VL_AD/verify.json"
assert_exit 0 verifyloop.sh "$(vl_fail "$E1")"
assert_exit 0 verifyloop.sh "$(vl_fail "$E1")"
assert_exit 0 verifyloop.sh "$(vl_fail "$E1")"
assert_exit 2 verifyloop.sh "$BG"
rm -f "$VL_AD/verify.json"
