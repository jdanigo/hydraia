# blastgate.sh plan-scope gate — edits must stay inside the frozen plan's **Files:**.
SG_REPO="$(git rev-parse --show-toplevel)"
SG_PLAN="$HYDRAIA_DOCS_DIR/plans/_scope-fixture.md"
mkdir -p "$HYDRAIA_DOCS_DIR/plans"
cat > "$SG_PLAN" <<'PLAN'
## Task 1 — Cart total
**Files:** Modify `src/cart/total.ts:12`, `src/cart/total.test.ts`;
Create `src/tax/` helpers.
**Verify:** `npx vitest run src/cart` → pass
## Task 2 — Styles
**Files:** `src/ui/*.css`, `src/api/{get,put}.ts`
- [ ] Verify: `npm run lint`
PLAN
printf '%s\n' "$SG_PLAN" > "$HYDRAIA_DOCS_DIR/.active-plan"
rm -rf "$HYDRAIA_DOCS_DIR/.agents/edited-files" "$HYDRAIA_DOCS_DIR/.agents/edited-files.runid"
sg() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$SG_REPO" "$1"; }
assert_exit 0 blastgate.sh "$(sg src/cart/total.ts)"          # declared (":12" stripped)
assert_exit 0 blastgate.sh "$(sg src/cart/total.test.ts)"
assert_exit 0 blastgate.sh "$(sg src/tax/rates.ts)"           # dir prefix on continuation line
assert_exit 0 blastgate.sh "$(sg src/ui/button.css)"          # glob
assert_exit 0 blastgate.sh "$(sg src/api/put.ts)"             # brace list
assert_exit 0 blastgate.sh "$(sg package-lock.json)"          # lockfile always allowed
assert_exit 0 blastgate.sh "$(sg README.md)"                  # markdown exempt
assert_stderr "plan-scope gate" blastgate.sh "$(sg src/checkout/pay.ts)"
assert_exit 2 blastgate.sh "$(sg src/api/delete.ts)"
assert_exit 0 blastgate.sh "$(sg src/checkout/pay.ts)" HYDRAIA_SCOPE_GATE=warn
assert_exit 0 blastgate.sh "$(sg src/checkout/pay.ts)" HYDRAIA_SCOPE_GATE=off
assert_exit 0 blastgate.sh "$(sg src/checkout/pay.ts)" HYDRAIA_ALLOW_DIRECT=1
# Legacy plan without any **Files:** declarations → no scope gate.
printf '## Task 1 — legacy\nDo the thing.\n' > "$SG_PLAN"
assert_exit 0 blastgate.sh "$(sg src/checkout/pay.ts)"
rm -f "$SG_PLAN" "$HYDRAIA_DOCS_DIR/.active-plan"
