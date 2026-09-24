# baseline.sh — records pre-existing failures before a run (Phase 0 helper).
BL_REPO="$(git rev-parse --show-toplevel)"
BL_OUT="$HYDRAIA_DOCS_DIR/.baseline-failures"
bl_check() { # bl_check <label> <expected-substring> <output>
  if printf '%s' "$3" | grep -qF "$2"; then PASS=$((PASS+1)); printf '  ok   baseline %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL baseline %s (want %s)\n' "$1" "$2"; fi
}
rm -f "$BL_OUT"
o="$(bash "$HOOKS_DIR/baseline.sh" -- true)"
bl_check clean "BASELINE: CLEAN" "$o"
bl_check file-written "# head=" "$(cat "$BL_OUT" 2>/dev/null)"
o="$(bash "$HOOKS_DIR/baseline.sh" -- sh -c 'echo "FAIL src/a.test.ts > adds (12ms)"; echo "AssertionError: expected 2 to be 3"; exit 1')"
bl_check preexisting "BASELINE: 2 pre-existing" "$o"
bl_check duration-stripped "FAIL src/a.test.ts > adds (<dur>)" "$(cat "$BL_OUT")"
o="$(HYDRAIA_BASELINE_TIMEOUT=1 bash "$HOOKS_DIR/baseline.sh" -- sh -c 'echo started; sleep 5')"
bl_check timeout "BASELINE: TIMEOUT after 1s" "$o"
bash "$HOOKS_DIR/baseline.sh" >/dev/null 2>&1; bl_code=$?
bl_check usage-exit "64" "$bl_code"
rm -f "$BL_OUT"
