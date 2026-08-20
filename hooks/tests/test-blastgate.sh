REPO="$(git rev-parse --show-toplevel)"
mkdir -p "$REPO/docs/hydraia"   # opt-in: make this repo a hydraia repo for the test
DENY="{\"tool_input\":{\"file_path\":\"$REPO/auth/login.ts\"}}"
OK="{\"tool_input\":{\"file_path\":\"$REPO/src/util.ts\"}}"
MD="{\"tool_input\":{\"file_path\":\"$REPO/README.md\"}}"
assert_exit 2 blastgate.sh "$DENY"
assert_exit 0 blastgate.sh "$OK"
assert_exit 0 blastgate.sh "$MD"
assert_exit 0 blastgate.sh "$DENY" HYDRAIA_ALLOW_DIRECT=1
assert_exit 0 blastgate.sh "$DENY" HYDRAIA_PATH_GATE=off
assert_stderr "blast-radius" blastgate.sh "$DENY"
