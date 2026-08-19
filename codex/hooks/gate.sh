#!/usr/bin/env bash
# Codex PreToolUse gate: block file edits until a frozen plan / approval marker
# exists. Mirrors the Claude hydraia spec-drive gate. Reads Codex hook JSON on
# stdin (tool, args, cwd); resolves the project and checks for the marker.
set -euo pipefail
payload="$(cat 2>/dev/null || true)"
proj="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -z "$proj" ] && proj="${PWD}"
# escape hatch (human-set), same spirit as Claude gate
[ "${HYDRAIA_ALLOW_DIRECT:-}" = "1" ] && exit 0
# approval markers (any one opens the gate)
for m in ".gate-approved" "docs/hydraia/.quick-approved" ".hydraia/plan-frozen"; do
  [ -f "$proj/$m" ] && exit 0
done
echo '{"decision":"block","reason":"[hydraia] spec-drive gate: no frozen plan / approval marker — edits blocked until a plan is approved. Run the hydraia pipeline or set HYDRAIA_ALLOW_DIRECT=1."}'
echo "[hydraia] BLOCKED: apply_patch before plan approval." >&2
exit 2
