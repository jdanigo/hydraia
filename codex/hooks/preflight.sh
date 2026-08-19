#!/usr/bin/env bash
# Codex SessionStart hook: inject hydraia pipeline context (additionalContext),
# mirroring the Claude preflight. Kept lightweight; no network.
set -euo pipefail
cat 2>/dev/null >/dev/null || true
ctx="Hydraia pipeline active (Codex). Follow the spec-drive contract: triage → analyze → spec+threat model → plan+self-review → sub-agent execution (executors=gpt-5.6-luna) → double review (reviewers=gpt-5.6-sol) → verify. Edits are gated until a plan is frozen."
printf '{"hookSpecificOutput":{"additionalContext":%s}}\n' "$(printf '%s' "$ctx" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
exit 0
