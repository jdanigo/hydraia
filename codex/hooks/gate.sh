#!/usr/bin/env bash
# Codex PreToolUse gate: block file edits until a frozen plan / approval marker
# exists. Mirrors the Claude hydraia spec-drive gate. Reads Codex hook JSON on
# stdin (tool, args, cwd); resolves the project and checks for the marker.
set -euo pipefail
payload="$(cat 2>/dev/null || true)"
proj="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -z "$proj" ] && proj="${PWD}"
tool="$(printf '%s' "$payload" | sed -n 's/.*"tool"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
if [ "$tool" = "shell" ]; then
  cmd="$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  case "$cmd" in
    *">"*|*">>"*|*" tee "*|*"rm "*|*"mv "*|*"git commit"*|*"git apply"*) : ;;  # write → fall through to gate
    *) exit 0 ;;  # read-only shell → allow
  esac
fi
# escape hatch (human-set), same spirit as Claude gate
[ "${HYDRAIA_ALLOW_DIRECT:-}" = "1" ] && exit 0
# approval markers (any one opens the gate)
for m in ".gate-approved" "docs/hydraia/.quick-approved" ".hydraia/plan-frozen"; do
  [ -f "$proj/$m" ] && exit 0
done
# Write shell commands: block via exit code only (no stdout JSON) — the shell
# matcher's block signal is exit-code-driven; stdout stays reserved for
# apply_patch's decision payload so tool-runtime parsers aren't confused by a
# JSON body on a shell invocation.
if [ "$tool" = "shell" ]; then
  echo "[hydraia] BLOCKED: write shell command before plan approval." >&2
  exit 2
fi
echo '{"decision":"block","reason":"[hydraia] spec-drive gate: no frozen plan / approval marker — edits blocked until a plan is approved. Run the hydraia pipeline or set HYDRAIA_ALLOW_DIRECT=1."}'
echo "[hydraia] BLOCKED: apply_patch before plan approval." >&2
exit 2
