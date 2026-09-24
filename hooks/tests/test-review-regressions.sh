# Regression tests for the v0.22.0 judge review findings (one block per finding).
RR_REPO="$(git rev-parse --show-toplevel)"
RR_AD="$HYDRAIA_DOCS_DIR/.agents"; mkdir -p "$RR_AD"
rr_check() { # rr_check <label> <cond-exit> ; cond-exit 0 = pass
  if [ "$2" = 0 ]; then PASS=$((PASS+1)); printf '  ok   review %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL review %s\n' "$1"; fi
}
rr_fail() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUseFailure","tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]},"error":sys.argv[3]}))' "$RR_REPO" "$1" "$2"; }

# R1 — ordinary failing commands that merely MENTION a test tool are not verify runs,
#      and a bare "Error: Exit code 1" is never recorded (would share one signature).
rm -f "$RR_AD/verify.json"; touch "$HYDRAIA_DOCS_DIR/.active-plan"
for c in 'test -f jest.config.js' 'ls tsconfig.json && which tsc' 'rg -l vitest src' 'git commit -m "bump pytest"'; do
  printf '%s' "$(rr_fail "$c" 'Error: Exit code 1')" | "$HOOKS_DIR/verifyloop.sh" >/dev/null 2>&1
done
printf '%s' "$(rr_fail 'npm test' 'Error: Exit code 1')" | "$HOOKS_DIR/verifyloop.sh" >/dev/null 2>&1
printf '%s' "$(rr_fail 'npm test' 'Error: Exit code 1')" | "$HOOKS_DIR/verifyloop.sh" >/dev/null 2>&1
printf '%s' "$(rr_fail 'npm test' 'Error: Exit code 1')" | "$HOOKS_DIR/verifyloop.sh" >/dev/null 2>&1
VP='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$RR_REPO"'","tool_input":{"command":"npm test"}}'
assert_exit 0 verifyloop.sh "$VP"                                   # never stalled by noise
# ...but a real runner at a segment start still counts (cd dir && env + timeout wrapper).
rm -f "$RR_AD/verify.json"
E="$(printf 'Error: Exit code 1\nFAIL a.test.ts > x\nAssertionError: expected 1 to be 2')"
printf '%s' "$(rr_fail 'cd web && CI=1 timeout 300 npx vitest run a.test.ts' "$E")" | "$HOOKS_DIR/verifyloop.sh" >/dev/null 2>&1
assert_stderr "NO PROGRESS" verifyloop.sh "$(rr_fail 'cd web && CI=1 timeout 300 npx vitest run a.test.ts' "$E")"

# R2 — a pre-existing failure stays PRE-EXISTING when the pass/fail COUNT line changes.
rm -f "$RR_AD/verify.json"
B="$(printf 'FAIL legacy.test.ts > old\nAssertionError: expected 3 to be 4\nTests  1 failed | 40 passed (41)')"
N="$(printf 'Error: Exit code 1\nFAIL legacy.test.ts > old\nAssertionError: expected 3 to be 4\nTests  1 failed | 41 passed (42)')"
printf '# head=x ts=0\n' > "$HYDRAIA_DOCS_DIR/.baseline-failures"
printf '%s' "$B" | python3 "$HOOKS_DIR/lib/failsig.py" lines >> "$HYDRAIA_DOCS_DIR/.baseline-failures"
assert_stderr "PRE-EXISTING" verifyloop.sh "$(rr_fail 'npm test' "$N")"
assert_stderr "PRE-EXISTING" verifyloop.sh "$(rr_fail 'npm test' "$N")"
assert_stderr "PRE-EXISTING" verifyloop.sh "$(rr_fail 'npm test' "$N")"
rm -f "$HYDRAIA_DOCS_DIR/.baseline-failures" "$RR_AD/verify.json"

# R3 — scope gate: blank line before the list, `Create: path` spans, dir without slash.
mkdir -p "$RR_REPO/hooks/tests/_fixture_dir"
RP="$HYDRAIA_DOCS_DIR/plans/_rr-scope.md"; mkdir -p "$HYDRAIA_DOCS_DIR/plans"
printf '## Task 1 — A\n**Files:**\n\n- `Create: src/new.ts`\n- Modify: `src/b.ts`\n- `hooks/tests/_fixture_dir`\n\n**Verify:** `npm test`\n' > "$RP"
printf '%s\n' "$RP" > "$HYDRAIA_DOCS_DIR/.active-plan"
sgp() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$RR_REPO" "$1"; }
assert_exit 0 blastgate.sh "$(sgp src/new.ts)"
assert_exit 0 blastgate.sh "$(sgp src/b.ts)"
assert_exit 0 blastgate.sh "$(sgp hooks/tests/_fixture_dir/x.sh)"
assert_exit 2 blastgate.sh "$(sgp src/other.ts)"
# R8b — a Write to a not-yet-existing dir OUTSIDE the repo is not this repo's scope.
assert_exit 0 blastgate.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/claude-501/hy-nonexistent-dir/deep/x.ts"}}'
rmdir "$RR_REPO/hooks/tests/_fixture_dir"; rm -f "$RP"

# R4 — "## Tasks" section titles and headings inside code fences are not tasks.
PP="$HYDRAIA_DOCS_DIR/plans/_rr-plan.md"
printf '## Tasks\nOverview.\n\n```md\n## Task 9 — example\n```\n## Task 1 — A\n**Files:** `src/a.ts`\n**Step 2: Verify** it passes\n' > "$PP"
PCP="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"printf \"%s\\n\" \""+sys.argv[1]+"\" > \""+sys.argv[2]+"/.active-plan\""}}))' "$PP" "$HYDRAIA_DOCS_DIR")"
assert_exit 0 plancheck.sh "$PCP"
rm -f "$PP"

# R5 — a multi-line description must not corrupt the subagent_type (judge stays allowed).
rm -f "$HYDRAIA_DOCS_DIR/.active-plan"
ML="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Agent","cwd":sys.argv[1],"tool_input":{"subagent_type":"hydraia:hydraia-reviewer","model":"opus","description":"whole-branch\nreview pass 1"}}))' "$RR_REPO")"
assert_exit 0 agents.sh "$ML"

# R6 — the Opus-gate message renders on macOS /bin/bash 3.2 (no "bad substitution").
og_err="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Agent","cwd":"%s","tool_input":{"subagent_type":"general-purpose","description":"x"}}' "$RR_REPO" | /bin/bash "$HOOKS_DIR/agents.sh" 2>&1 >/dev/null)"
printf '%s' "$og_err" | grep -q "BLOCKED: Opus gate" && ! printf '%s' "$og_err" | grep -q "bad substitution"; rr_check "opus-gate message on bash 3.2" $?

# R7 — the model cannot reset breaker state (Bash or Edit/Write); routing stays writable.
assert_exit 2 safety-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -f $HYDRAIA_DOCS_DIR/.agents/verify.json\"}}"
assert_exit 2 safety-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"printf '{}' > docs/hydraia/.agents/ledger.json\"}}"
assert_exit 2 blastgate.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HYDRAIA_DOCS_DIR/.agents/verify.json\"}}"
assert_exit 0 safety-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"printf 'balanced\\\\n' > docs/hydraia/.agents/routing\"}}"
# The STALLED message no longer hands the model a reset command.
rm -f "$RR_AD/verify.json"; touch "$HYDRAIA_DOCS_DIR/.active-plan"
for i in 1 2; do printf '%s' "$(rr_fail 'npm test' "$E")" | "$HOOKS_DIR/verifyloop.sh" >/dev/null 2>&1; done
st="$(printf '%s' "$(rr_fail 'npm test' "$E")" | "$HOOKS_DIR/verifyloop.sh" 2>&1 >/dev/null)"
printf '%s' "$st" | grep -q "STALLED" && ! printf '%s' "$st" | grep -q "rm "; rr_check "stalled message has no reset command" $?

# R8a — a watcher in the background is not blocked; R8d — backslashes survive (\c, \n).
rm -f "$RR_AD/verify.json"   # R7 left the run STALLED; isolate the background-guard case
WB='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$RR_REPO"'","tool_input":{"command":"npx vitest --watch","run_in_background":true}}'
assert_exit 0 verifyloop.sh "$WB"
rm -f "$RR_AD/verify.json"
BS="$(printf 'Error: Exit code 1\nFAIL C:\\\\cfg\\\\new.test.ts > x\nAssertionError: expected 1 to be 2')"
printf '%s' "$(rr_fail 'npm test' "$BS")" | "$HOOKS_DIR/verifyloop.sh" >/dev/null 2>&1
bs_err="$(printf '%s' "$(rr_fail 'npm test' "$BS")" | "$HOOKS_DIR/verifyloop.sh" 2>&1 >/dev/null)"
printf '%s' "$bs_err" | grep -q "At 3x verification is blocked"; rr_check "message not truncated by backslash escapes" $?
rm -f "$RR_AD/verify.json" "$HYDRAIA_DOCS_DIR/.active-plan"
