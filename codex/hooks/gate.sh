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
# write escalates to PermissionRequest. This hook is the deterministic, FAIL-CLOSED
# arbiter: any payload it cannot parse is blocked, never allowed. The sandbox is never
# flipped — the model cannot self-elevate.
#
# Pre-freeze policy (no marker): apply_patch -> deny; shell write -> ask (a human is
# present, because Codex hooks are interactive-only), or deny when HYDRAIA_GATE_STRICT=1.
# The frozen-plan marker is created by the HUMAN (or HYDRAIA_ALLOW_DIRECT=1), never by the
# model — that is the trust anchor. With a marker present every write is allowed
# (autonomous half). Reads never escalate, so they run free.
set -euo pipefail

payload="$(cat 2>/dev/null || true)"

_log() { [ -n "${HYDRAIA_GATE_LOG:-}" ] || return 0; printf '%s\n' "$*" >> "$HYDRAIA_GATE_LOG" 2>/dev/null || true; }
# _field: first quoted-scalar match for a key. Ends with `sed -n '1p'` (consumes all
# input, so the upstream sed never takes SIGPIPE) — safe under `set -euo pipefail`.
_field() { printf '%s' "$payload" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | sed -n '1p'; }

# emit a fail-closed block for BOTH event shapes, then exit non-zero.
_fail_closed() {
  local why="$1"
  _log "{\"event\":\"unparsed\",\"decision\":\"deny\",\"reason\":\"$why\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"deny","permissionDecisionReason":"[hydraia] %s"}}\n' "$why"
  echo "{\"decision\":\"block\",\"reason\":\"[hydraia] $why\"}"
  echo "[hydraia] BLOCKED (fail-closed): $why" >&2
  exit 2
}

proj="$(_field cwd)"; [ -z "$proj" ] && proj="${PWD}"
tool="$(_field tool_name)"
event="$(_field hook_event_name)"; [ -z "$event" ] && event="$(_field hookEventName)"

# Fail closed: a hook fired but the payload is unparseable (empty stdin, garbled, or an
# unrecognized shape yielding neither tool nor event). Default for "cannot understand
# the request" is BLOCK, never allow. (A genuine read carries a tool_name, so this never
# false-blocks reads.)
[ -z "$payload" ] && _fail_closed "empty hook payload"
{ [ -z "$tool" ] && [ -z "$event" ]; } && _fail_closed "hook payload names neither tool nor event"

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
    elif [ -z "$tool" ]; then
      decision="deny";  reason="[hydraia] spec-drive gate: unidentified write tool — blocked (fail-closed)."
    elif [ "${HYDRAIA_GATE_STRICT:-}" = "1" ]; then
      decision="deny";  reason="[hydraia] spec-drive gate (strict): no frozen plan — write blocked. Freeze a plan or set HYDRAIA_ALLOW_DIRECT=1."
    else
      decision="ask";   reason="[hydraia] spec-drive gate: no frozen plan — write needs human approval (interactive design half)."
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
