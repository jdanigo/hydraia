# agents.sh Opus gate — Opus only judges; executors on Opus only under Max-quality routing.
OG_REPO="$(git rev-parse --show-toplevel)"
OG_AD="$HYDRAIA_DOCS_DIR/.agents"; mkdir -p "$OG_AD"
rm -f "$OG_AD/routing" "$OG_AD/ledger.json" "$OG_AD/dispatched" "$OG_AD/finished" "$OG_AD/runid"
rm -f "$HYDRAIA_DOCS_DIR/.active-plan"   # gate applies with or without an active run
og() { # og <subagent_type> <model or ''>
  python3 -c 'import json,sys
ti={"subagent_type":sys.argv[2],"description":"x"}
if sys.argv[3]: ti["model"]=sys.argv[3]
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Agent","cwd":sys.argv[1],"tool_input":ti}))' "$OG_REPO" "$1" "$2"
}
assert_stderr "Opus gate" agents.sh "$(og hydraia:hydraia-executor opus)"   # executor asks Opus
assert_exit 2 agents.sh "$(og general-purpose '')"                       # inherits Opus
assert_exit 2 agents.sh "$(og Explore '')"
assert_exit 0 agents.sh "$(og Explore sonnet)"                           # explicit Sonnet
assert_exit 0 agents.sh "$(og hydraia:hydraia-reviewer opus)"            # judge
assert_exit 0 agents.sh "$(og security-reviewer '')"                     # judge, pinned
assert_exit 0 agents.sh "$(og hydraia:typescript-reviewer '')"           # pinned sonnet
assert_exit 0 agents.sh "$(og hydraia-executor opus)" HYDRAIA_ALLOW_OPUS=1
assert_exit 0 agents.sh "$(og general-purpose '')" HYDRAIA_OPUS_GATE=warn
assert_exit 0 agents.sh "$(og general-purpose '')" HYDRAIA_OPUS_GATE=off
# Max-quality routing (written by the Phase-3 picker) lets executors use Opus.
printf 'max-quality\n' > "$OG_AD/routing"
assert_exit 0 agents.sh "$(og hydraia-executor opus)"
assert_exit 2 agents.sh "$(og general-purpose opus)"                     # still not generic agents
printf 'balanced\n' > "$OG_AD/routing"
assert_exit 2 agents.sh "$(og hydraia-executor opus)"
rm -f "$OG_AD/routing"
