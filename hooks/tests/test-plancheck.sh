# plancheck.sh — "## Task" headings are scanned; tasks need a contract (Files + Verify).
PC_DIR="$HYDRAIA_DOCS_DIR/plans"; mkdir -p "$PC_DIR"
PC_PLAN="$PC_DIR/_plancheck-fixture.md"
pc() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"printf \"%s\\n\" \""+sys.argv[1]+"\" > \""+sys.argv[2]+"/.active-plan\""}}))' "$PC_PLAN" "$HYDRAIA_DOCS_DIR"; }
# Contract-complete level-2 plan → allowed.
printf '## Task 1 — A\n**Files:** Modify `src/a.ts`\n**Verify:** `npm test` → pass\n## Task 2 — B\n**Files:** Create `src/b.ts`\n- [ ] Verify: `npm test`\n' > "$PC_PLAN"
assert_exit 0 plancheck.sh "$(pc)"
# Missing Verify on Task 2 → blocked, names the task.
printf '## Task 1 — A\n**Files:** Modify `src/a.ts`\n**Verify:** `npm test`\n## Task 2 — B\n**Files:** Create `src/b.ts`\n' > "$PC_PLAN"
assert_stderr "Task 2 — B  (missing: Verify)" plancheck.sh "$(pc)"
# Missing Files → blocked.
printf '### Task 1 — A\nDo it.\n**Verify:** `npm test`\n' > "$PC_PLAN"
assert_stderr "missing: **Files:**" plancheck.sh "$(pc)"
# planContract=off disables only the contract rule.
assert_exit 0 plancheck.sh "$(pc)" HYDRAIA_PLAN_CONTRACT=off
# Level-2 heading with a reference smell is now scanned (was skipped: "###" only).
printf '## Task 1 — A\n**Files:** Modify `src/a.ts`\nImplement per the spec.\n**Verify:** `npm test`\n' > "$PC_PLAN"
assert_stderr "Not self-contained" plancheck.sh "$(pc)"
# This release's own plan satisfies the contract.
cp "$(git rev-parse --show-toplevel)/docs/hydraia/plans/2026-09-24-convergence.md" "$PC_PLAN"
assert_exit 0 plancheck.sh "$(pc)"
rm -f "$PC_PLAN"
