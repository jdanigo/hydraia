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
