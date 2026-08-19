#!/usr/bin/env bash
# Codex PreToolUse gate: block file edits until a frozen plan / approval marker
# exists. Mirrors the Claude hydraia spec-drive gate. Invoked for EVERY tool
# (hooks.json uses a catch-all matcher), so it must:
#   - gate `apply_patch` (the edit tool),
#   - gate any shell tool that WRITES (redirects, tee, rm/mv/cp, sed -i, in-place
#     writers, git commit/apply) — the demonstrated bypass was `printf … > file`,
#   - ALLOW read-only shell and all other (non-edit) tools.
# Reads Codex hook JSON on stdin (tool, args/command, cwd).
set -euo pipefail
payload="$(cat 2>/dev/null || true)"
proj="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -z "$proj" ] && proj="${PWD}"
tool="$(printf '%s' "$payload" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

is_edit=0
case "$tool" in
  apply_patch|patch|edit|write_file|create_file) is_edit=1 ;;
  shell|local_shell|exec|bash|command|shell_command|container.exec)
    # extract the command string from the payload (best-effort across arg shapes)
    cmd="$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -z "$cmd" ] && cmd="$(printf '%s' "$payload" | grep -oE '"command"[^]]*' | head -1 || true)"
    case "$cmd" in
      # write indicators anywhere in the command → gate it
      *">"*|*">>"*|*"|"*"tee"*|*" tee "*|*"rm "*|*"rm -"*|*"mv "*|*"cp "*|*"dd "*|\
      *"sed -i"*|*"truncate"*|*"git commit"*|*"git apply"*|*"git checkout"*|*"git reset"*|\
      *"tee "*|*"> "*|*">>"*|*"install -"*|*"chmod "*|*"mkdir "*|*"touch "*) is_edit=1 ;;
      "") is_edit=1 ;;   # unknown/unparsed command → gate (fail closed)
      *) is_edit=0 ;;    # clearly read-only shell → allow
    esac ;;
  *) is_edit=0 ;;         # any other tool (reads, listings, etc.) → allow
esac

[ "$is_edit" -eq 0 ] && exit 0

# It's a gated edit. Open the gate only via an explicit escape hatch or marker.
[ "${HYDRAIA_ALLOW_DIRECT:-}" = "1" ] && exit 0
for m in ".gate-approved" "docs/hydraia/.quick-approved" ".hydraia/plan-frozen"; do
  [ -f "$proj/$m" ] && exit 0
done

echo '{"decision":"block","reason":"[hydraia] spec-drive gate: no frozen plan / approval marker — edits blocked until a plan is approved (apply_patch and write-shell are gated). Freeze a plan, or set HYDRAIA_ALLOW_DIRECT=1."}'
echo "[hydraia] BLOCKED: edit before plan approval (tool=$tool)." >&2
exit 2
