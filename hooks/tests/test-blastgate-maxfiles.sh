# I1: the maxFiles set (edited-files) must reset per run, like the other counters.
# Proven behaviorally: pre-seed a STALE run's file set that already exceeds maxFiles and
# stamp a stale runid; arm a NEW run (fresh .active-plan mtime); a single benign edit must
# be ALLOWED because the stale set was truncated on the run change. Without the reset the
# carried-over 15 files + 1 would trip the enforced maxFiles cap and block (exit 2).
REPO="$(git rev-parse --show-toplevel)"
mkdir -p "$REPO/docs/hydraia"                         # opt-in
AGD="$REPO/docs/hydraia/.agents"; mkdir -p "$AGD"
touch "$REPO/docs/hydraia/.active-plan"               # arm a run (fresh mtime)
# Seed a stale run: 15 distinct files (> maxFiles=10) and a runid that cannot match mtime.
: > "$AGD/edited-files"
for i in $(seq 1 15); do printf 'stale/file-%s.ts\n' "$i" >> "$AGD/edited-files"; done
printf '1' > "$AGD/edited-files.runid"
OKF="{\"tool_input\":{\"file_path\":\"$REPO/src/util.ts\"}}"
# With per-run reset the stale set is dropped, so this one edit passes even when enforced.
assert_exit 0 blastgate.sh "$OKF" HYDRAIA_MAX_FILES_ENFORCE=true
# The runid file now records the current run (no longer the stale "1").
if [ "$(cat "$AGD/edited-files.runid" 2>/dev/null)" != "1" ]; then
  PASS=$((PASS+1)); printf '  ok   blastgate.sh edited-files.runid refreshed\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL blastgate.sh edited-files.runid not refreshed\n'
fi
# The stale 15-file set was truncated (set now holds only the single new edit).
if [ "$(sort -u "$AGD/edited-files" 2>/dev/null | wc -l | tr -d ' ')" = "1" ]; then
  PASS=$((PASS+1)); printf '  ok   blastgate.sh edited-files reset to new run\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL blastgate.sh edited-files not reset\n'
fi
