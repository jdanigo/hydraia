#!/usr/bin/env bash
# Fixture-driven tests for gate.sh — both events, no Codex needed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/gate.sh"
PROJ="$(mktemp -d)"; trap 'rm -rf "$PROJ"' EXIT
pass=0; fail=0
run() { # name | stdin-json | expect-substr | expect-exit
  local name="$1" json="$2" want="$3" wantrc="$4" out rc
  out="$(printf '%s' "$json" | HYDRAIA_ALLOW_DIRECT= bash "$GATE" 2>/dev/null)"; rc=$?
  local ok=1
  [ -n "$want" ] && { printf '%s' "$out" | grep -q "$want" || ok=0; }
  [ -z "$want" ] && { [ -z "$out" ] || ok=0; }
  if [ "$ok" = 1 ] && [ "$rc" = "$wantrc" ]; then
    echo "  ok: $name"; pass=$((pass+1))
  else
    echo "  FAIL: $name (rc=$rc want=$wantrc out=$out)"; fail=$((fail+1))
  fi
}
J() { printf '{"cwd":"%s","hook_event_name":"%s","tool_name":"%s","cmd":"%s"}' "$PROJ" "$1" "$2" "$3"; }

# PermissionRequest, no marker:
run "PR shell printf> denied-as-ask"   "$(J PermissionRequest exec_command 'printf hi > hello.txt')" '"permissionDecision":"ask"'   0
run "PR apply_patch denied"            "$(J PermissionRequest apply_patch '')"                        '"permissionDecision":"deny"'  0
# PermissionRequest, marker present → allow:
touch "$PROJ/.gate-approved"
run "PR shell allowed with marker"     "$(J PermissionRequest exec_command 'printf hi > hello.txt')" '"permissionDecision":"allow"' 0
run "PR apply_patch allowed w/ marker" "$(J PermissionRequest apply_patch '')"                        '"permissionDecision":"allow"' 0
rm -f "$PROJ/.gate-approved"
# PreToolUse legacy (regression):
run "PTU apply_patch blocked"          "$(J PreToolUse apply_patch '')"                               '"decision":"block"'           2
run "PTU shell read allowed"           "$(J PreToolUse exec_command 'ls -la')"                        ''                             0
run "PTU shell write blocked"          "$(J PreToolUse exec_command 'printf hi > x')"                 '"decision":"block"'           2

# Fail-closed on unparseable input (the reviewed fail-open):
run "empty payload fails closed"       ""                                                             '"permissionDecision":"deny"' 2
run "no tool nor event fails closed"   '{"cwd":"/x","foo":"bar"}'                                     '"permissionDecision":"deny"' 2
run "PR empty tool fails closed"       "$(J PermissionRequest '' 'printf hi > x')"                    '"permissionDecision":"deny"' 0

# Strict knob: shell source write pre-freeze becomes deny instead of ask:
strict() { local out rc; out="$(printf '%s' "$2" | HYDRAIA_ALLOW_DIRECT= HYDRAIA_GATE_STRICT=1 bash "$GATE" 2>/dev/null)"; rc=$?
  if printf '%s' "$out" | grep -q "$3" && [ "$rc" = "$4" ]; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1 (rc=$rc out=$out)"; fail=$((fail+1)); fi; }
strict "PR shell strict=deny"          "$(J PermissionRequest exec_command 'printf hi > x')"          '"permissionDecision":"deny"' 0

echo "gate.test: $pass passed, $fail failed"
[ "$fail" = 0 ]
