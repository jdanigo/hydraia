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
