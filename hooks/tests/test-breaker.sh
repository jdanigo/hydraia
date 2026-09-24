REPO="$(git rev-parse --show-toplevel)"
AD="$REPO/docs/hydraia/.agents"; mkdir -p "$AD"
rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"
touch "$REPO/docs/hydraia/.active-plan"
P='{"hook_event_name":"PreToolUse","tool_name":"Task","cwd":"'"$REPO"'","tool_input":{"subagent_type":"hydraia-executor","description":"[task:widget] build widget"}}'
# First two dispatches allowed (attempts 1,2 <= maxTaskRetries=2), third blocked.
assert_exit 0 agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
assert_exit 0 agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
assert_exit 2 agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
assert_stderr "breaker" agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
# Bypass lifts it.
assert_exit 0 agents.sh "$P" HYDRAIA_ALLOW_DIRECT=1

# --- C1: review CYCLES are counted, reviewer FAN-OUT is not ------------------
# The whole-branch Pass-1 reviewer (hydraia-reviewer) is the only review-cycle-counted
# agent. Three consecutive dispatches in one run go allow, allow, BLOCK at maxReviewCycles=2.
rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"
touch "$REPO/docs/hydraia/.active-plan"   # single run: keep this mtime across the sequence
RV='{"hook_event_name":"PreToolUse","tool_name":"Task","cwd":"'"$REPO"'","tool_input":{"subagent_type":"hydraia-reviewer","description":"whole-branch review pass"}}'
assert_exit 0 agents.sh "$RV" HYDRAIA_MAX_REVIEW_CYCLES=2
assert_exit 0 agents.sh "$RV" HYDRAIA_MAX_REVIEW_CYCLES=2
assert_exit 2 agents.sh "$RV" HYDRAIA_MAX_REVIEW_CYCLES=2
assert_stderr "review cycles" agents.sh "$RV" HYDRAIA_MAX_REVIEW_CYCLES=2

# A specialized Phase-5 reviewer is EXEMPT from the breaker: Phase 5 fans out five
# reviewers in the FIRST pass, so none of them may be cycle-counted. Four consecutive
# security-reviewer dispatches all pass the breaker (never blocked by review cycles).
rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"
touch "$REPO/docs/hydraia/.active-plan"
SR='{"hook_event_name":"PreToolUse","tool_name":"Task","cwd":"'"$REPO"'","tool_input":{"subagent_type":"security-reviewer","description":"security review"}}'
assert_exit 0 agents.sh "$SR" HYDRAIA_MAX_REVIEW_CYCLES=2
assert_exit 0 agents.sh "$SR" HYDRAIA_MAX_REVIEW_CYCLES=2
assert_exit 0 agents.sh "$SR" HYDRAIA_MAX_REVIEW_CYCLES=2
assert_exit 0 agents.sh "$SR" HYDRAIA_MAX_REVIEW_CYCLES=2

# --- v0.22: current CC names the tool "Agent" (not "Task"); caps must still apply ----
rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"
touch "$REPO/docs/hydraia/.active-plan"
PA='{"hook_event_name":"PreToolUse","tool_name":"Agent","cwd":"'"$REPO"'","tool_input":{"subagent_type":"hydraia:hydraia-executor","description":"[task:gadget] build gadget"}}'
assert_exit 0 agents.sh "$PA" HYDRAIA_MAX_TASK_RETRIES=1
assert_exit 2 agents.sh "$PA" HYDRAIA_MAX_TASK_RETRIES=1

# Namespaced whole-branch reviewer ("hydraia:hydraia-reviewer") is review-cycle-counted.
rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"
touch "$REPO/docs/hydraia/.active-plan"
NRV='{"hook_event_name":"PreToolUse","tool_name":"Agent","cwd":"'"$REPO"'","tool_input":{"subagent_type":"hydraia:hydraia-reviewer","description":"whole-branch review"}}'
assert_exit 0 agents.sh "$NRV" HYDRAIA_MAX_REVIEW_CYCLES=1
assert_stderr "review cycles" agents.sh "$NRV" HYDRAIA_MAX_REVIEW_CYCLES=1

# --- v0.22: [fix:<slug>] dispatches — per-finding cap + per-run fix budget ------------
rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"
touch "$REPO/docs/hydraia/.active-plan"
fx() { printf '{"hook_event_name":"PreToolUse","tool_name":"Agent","cwd":"%s","tool_input":{"subagent_type":"hydraia-executor","description":"[fix:%s] fix it"}}' "$REPO" "$1"; }
assert_exit 0 agents.sh "$(fx null-total)" HYDRAIA_MAX_FIX_ATTEMPTS=2 HYDRAIA_MAX_FIX_DISPATCHES=3
assert_exit 0 agents.sh "$(fx null-total)" HYDRAIA_MAX_FIX_ATTEMPTS=2 HYDRAIA_MAX_FIX_DISPATCHES=3
assert_stderr "fix \"null-total\" exhausted" agents.sh "$(fx null-total)" HYDRAIA_MAX_FIX_ATTEMPTS=2 HYDRAIA_MAX_FIX_DISPATCHES=3
# The blocked 3rd attempt did not burn budget: run total is 2 → one more distinct fix fits.
assert_exit 0 agents.sh "$(fx tax-rate)" HYDRAIA_MAX_FIX_ATTEMPTS=2 HYDRAIA_MAX_FIX_DISPATCHES=3
assert_stderr "fix budget for this run exhausted" agents.sh "$(fx other)" HYDRAIA_MAX_FIX_ATTEMPTS=2 HYDRAIA_MAX_FIX_DISPATCHES=3
rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"
