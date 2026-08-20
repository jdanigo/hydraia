#!/usr/bin/env bash
# Codex write-gate — spec-drive: block filesystem writes until a frozen plan /
# approval marker exists. Handles TWO Codex hook events with different shapes:
#
#   PreToolUse        — fires for apply_patch (NOT exec_command). Legacy path,
#                       preserved: {"decision":"block",...} + exit 2 when gated.
#   PermissionRequest — fires for EVERY escalated write under sandbox_mode=read-only.
#                       This is how exec_command writes get gated (PreToolUse never
#                       fires for them). Emits permissionDecision allow|deny|ask.
#
# Airtight model: setup.sh pins sandbox_mode=read-only, so the macOS seatbelt kernel
# blocks all writes at the OS level (printf>, python -c, node, heredoc alike) and every
# write escalates to PermissionRequest. This hook is the deterministic, fail-closed
# arbiter. The sandbox is never flipped: with a frozen-plan marker the hook allows
# writes (autonomous half); without one it denies source edits (apply_patch) and asks
# the human for anything else (interactive design half / plan-marker bootstrap).
set -euo pipefail

payload="$(cat 2>/dev/null || true)"

_log() { [ -n "${HYDRAIA_GATE_LOG:-}" ] || return 0; printf '%s\n' "$*" >> "$HYDRAIA_GATE_LOG" 2>/dev/null || true; }
_field() { printf '%s' "$payload" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1; }

proj="$(_field cwd)"; [ -z "$proj" ] && proj="${PWD}"
tool="$(_field tool_name)"
event="$(_field hook_event_name)"; [ -z "$event" ] && event="$(_field hookEventName)"

# shared marker check
gate_open=0
[ "${HYDRAIA_ALLOW_DIRECT:-}" = "1" ] && gate_open=1
for m in ".gate-approved" "docs/hydraia/.quick-approved" ".hydraia/plan-frozen"; do
  [ -f "$proj/$m" ] && gate_open=1
done

# --- PermissionRequest branch (read-only sandbox → every write escalates here) ---
case "$event" in
  *[Pp]ermission[Rr]equest*)
    if [ "$gate_open" -eq 1 ]; then
      decision="allow"; reason="[hydraia] frozen-plan marker present — write allowed."
    elif [ "$tool" = "apply_patch" ]; then
      decision="deny";  reason="[hydraia] spec-drive gate: no frozen plan — source edits (apply_patch) blocked."
    else
      decision="ask";   reason="[hydraia] spec-drive gate: no frozen plan — write needs approval (interactive design half). Freeze a plan for autonomous writes."
    fi
    _log "{\"event\":\"PermissionRequest\",\"tool\":\"$tool\",\"decision\":\"$decision\",\"cwd\":\"$proj\"}"
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$decision" "$reason"
    exit 0
    ;;
esac

# --- PreToolUse branch (legacy) — preserved behavior ---
is_edit=0
case "$tool" in
  apply_patch|patch|edit|write_file|create_file) is_edit=1 ;;
  exec_command|shell|local_shell|exec|bash|command|shell_command|container.exec)
    cmd="$(_field cmd)"; [ -z "$cmd" ] && cmd="$(_field command)"
    case "$cmd" in
      *">"*|*">>"*|*"|"*"tee"*|*" tee "*|*"rm "*|*"rm -"*|*"mv "*|*"cp "*|*"dd "*|\
      *"sed -i"*|*"truncate"*|*"git commit"*|*"git apply"*|*"git checkout"*|*"git reset"*|\
      *"tee "*|*"> "*|*">>"*|*"install -"*|*"chmod "*|*"mkdir "*|*"touch "*) is_edit=1 ;;
      "") is_edit=1 ;;
      *) is_edit=0 ;;
    esac ;;
  *) is_edit=0 ;;
esac

[ "$is_edit" -eq 0 ] && exit 0
[ "$gate_open" -eq 1 ] && exit 0

_log "{\"event\":\"PreToolUse\",\"tool\":\"$tool\",\"decision\":\"block\",\"cwd\":\"$proj\"}"
echo '{"decision":"block","reason":"[hydraia] spec-drive gate: no frozen plan / approval marker — edits blocked until a plan is approved (apply_patch and write-shell are gated). Freeze a plan, or set HYDRAIA_ALLOW_DIRECT=1."}'
echo "[hydraia] BLOCKED: edit before plan approval (tool=$tool)." >&2
exit 2
