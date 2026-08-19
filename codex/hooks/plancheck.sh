#!/usr/bin/env bash
# Codex PreToolUse (plan-arm) hook: block arming a plan that still references the
# spec instead of inlining it (self-containment gate). Mirrors Claude plancheck.
set -euo pipefail
payload="$(cat 2>/dev/null || true)"
proj="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -z "$proj" ] && proj="${PWD}"
plan="$(printf '%s' "$payload" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
if [ -n "$plan" ] && [ -f "$proj/$plan" ] && grep -qiE 'see the spec|refer to the spec|per the spec' "$proj/$plan"; then
  echo '{"decision":"block","reason":"[hydraia] plan references the spec instead of inlining it — self-containment gate."}'
  exit 2
fi
exit 0
