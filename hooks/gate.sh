#!/usr/bin/env bash
# Hydraia spec-drive gate (PreToolUse on Edit/Write/MultiEdit).
#
# Enforces the pipeline's core promise: no source-code edit before a spec + plan
# exist. It makes "never skip a phase" a runtime guarantee instead of a prompt the
# model can rationalize past.
#
# It BLOCKS a code edit only when ALL of these hold:
#   - the target repo opts in (has a docs/hydraia/ directory), AND
#   - the human bypass is NOT set (HYDRAIA_ALLOW_DIRECT is empty/unset), AND
#   - the target is source code (not markdown, not under docs/hydraia/), AND
#   - no frozen plan is active (docs/hydraia/.active-plan missing or stale).
#
# The bypass is deliberately an env var, not a command: the decision to skip the
# pipeline is the human's, not the model's. To allow a direct edit:
#     export HYDRAIA_ALLOW_DIRECT=1
#
# On any internal error the gate ALLOWS (fail-open) — it must never wedge editing.
set -uo pipefail

FRESH_SECS=43200   # 12h — a stale .active-plan from an old run won't authorize edits

# Read the hook payload from stdin (Claude Code passes tool input as JSON).
payload="$(cat 2>/dev/null || true)"

# Extract the target file path. Prefer python3 (a Hydraia prerequisite); if it is
# missing or the payload is unparseable, fail open.
file_path=""
if command -v python3 >/dev/null 2>&1; then
  file_path="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    print(ti.get("file_path") or ti.get("path") or "")
except Exception:
    print("")
' 2>/dev/null || true)"
fi

# No path to reason about → allow.
[ -n "$file_path" ] || exit 0

# Human bypass — the only sanctioned way to skip the pipeline.
if [ -n "${HYDRAIA_ALLOW_DIRECT:-}" ]; then
  exit 0
fi

# Resolve the repo root for the file being edited.
dir="$(dirname "$file_path" 2>/dev/null || echo .)"
[ -d "$dir" ] || dir="."
repo="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0   # not in a git repo → not a Hydraia-managed edit, allow

# Opt-in: only enforce in repos that use Hydraia.
[ -d "$repo/docs/hydraia" ] || exit 0

# Exempt non-code artifacts: markdown (specs, plans, run logs, docs) and anything
# under docs/hydraia/ (the pipeline's own writes must never be blocked).
case "$file_path" in
  *.md|*.markdown) exit 0 ;;
esac
case "$file_path" in
  "$repo"/docs/hydraia/*|docs/hydraia/*) exit 0 ;;
esac

# Gate: a frozen plan must be active and fresh.
marker="$repo/docs/hydraia/.active-plan"
if [ -f "$marker" ]; then
  now="$(date +%s)"
  mtime="$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0)"
  if [ $(( now - mtime )) -lt "$FRESH_SECS" ]; then
    exit 0   # plan is frozen and current → code edits allowed
  fi
fi

# No active plan → block. Exit 2 tells Claude Code to reject the tool call and
# feed stderr back to the model.
cat >&2 <<EOF
[hydraia] BLOCKED: spec-drive gate.

You are editing source code before a frozen plan exists for this work.
Hydraia is spec-drive-design first — Phases 2 (spec + threat model) and 3
(plan + self-review) must complete before any code is written.

Do one of:
  • Run the pipeline: /hydraia:feature <what you are building>
    (or /hydraia:plan first to freeze the design, then execute).
  • If this edit is genuinely outside the pipeline and you (the human) accept
    the risk, set the bypass in your shell and retry:
        export HYDRAIA_ALLOW_DIRECT=1

Token cost or change size is NOT a reason to skip — proportionality is the
human's call, made via the bypass above, never the model's.
EOF
exit 2
