REPO="$(git rev-parse --show-toplevel)"
mkdir -p "$REPO/docs/hydraia/.agents"; touch "$REPO/docs/hydraia/.active-plan"
P='{"hook_event_name":"PreToolUse","tool_name":"Task","cwd":"'"$REPO"'","tool_input":{"subagent_type":"hydraia-executor","description":"[task:x] x"}}'
# Kill switch blocks.
assert_exit 2 agents.sh "$P" HYDRAIA_PAUSE=1
assert_stderr "paused" agents.sh "$P" HYDRAIA_PAUSE=1
# Cap of 0 never blocks (default).
assert_exit 0 agents.sh "$P" HYDRAIA_DAILY_TOKEN_CAP=0
