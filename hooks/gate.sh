#!/usr/bin/env bash
# Hydraia spec-drive gate (PreToolUse on Edit/Write/MultiEdit).
#
# Enforces the pipeline's core promise: no source-code edit before a spec + plan
# exist. It makes "never skip a phase" a runtime guarantee instead of a prompt the
# model can rationalize past.
#
# It BLOCKS a code edit only when ALL of these hold:
#   - the target repo opts in (registered in the global config, or has a resolved
#     artifacts dir / legacy docs/hydraia/ directory), AND
#   - the human bypass is NOT set (HYDRAIA_ALLOW_DIRECT is empty/unset), AND
#   - the target is source code (not markdown, not under the artifacts dir), AND
#   - no frozen plan is active (<artifacts dir>/.active-plan missing or stale).
#
# The bypass is deliberately an env var, not a command: the decision to skip the
# pipeline is the human's, not the model's. To allow a direct edit:
#     export HYDRAIA_ALLOW_DIRECT=1
#
# On any internal error the gate ALLOWS (fail-open) — it must never wedge editing.
set -uo pipefail

# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true

FRESH_SECS=43200   # 12h — a stale .active-plan from an old run won't authorize edits
QUICK_SECS=1800    # 30m — a human-approved quick edit is a short, single-burst window

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

# Resolve the artifacts base (in-repo docs/hydraia by default, or the external dir
# the user chose at the storage gate). Run from the repo so git-root resolution is
# correct even when the hook's cwd differs.
adir="$(cd "$repo" 2>/dev/null && hy_artifacts_dir)"
[ -n "$adir" ] || adir="$repo/docs/hydraia"

# Opt-in: enforce only in repos that use Hydraia — the resolved artifacts dir exists,
# OR the repo is registered in the global config (external mode leaves nothing in the
# repo), OR the legacy in-repo docs/hydraia/ exists.
if [ ! -d "$adir" ] \
   && [ -z "$(cd "$repo" 2>/dev/null && hy_repo_config artifactsDir "")" ] \
   && [ ! -d "$repo/docs/hydraia" ]; then
  exit 0
fi

# Spec-drive mode (config): off = never gate; relaxed = warn but allow;
# strict (default) = block. Env HYDRAIA_SPEC_DRIVE overrides the file.
SPEC_DRIVE="strict"
command -v hy_config >/dev/null 2>&1 && SPEC_DRIVE="$(hy_config specDrive strict HYDRAIA_SPEC_DRIVE)"
[ "$SPEC_DRIVE" = "off" ] && exit 0

# Exempt non-code artifacts: markdown (specs, plans, run logs, docs) and anything
# under docs/hydraia/ (the pipeline's own writes must never be blocked).
case "$file_path" in
  *.md|*.markdown) exit 0 ;;
esac
case "$file_path" in
  "$adir"/*|"$repo"/docs/hydraia/*|docs/hydraia/*) exit 0 ;;
esac

now="$(date +%s)"
fresh() { # $1=marker path, $2=max age secs → 0 if present and fresh
  [ -f "$1" ] || return 1
  local m
  m="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)"
  [ $(( now - m )) -lt "$2" ]
}

# Allow when a frozen plan is active (normal pipeline, Phase 3+).
fresh "$adir/.active-plan" "$FRESH_SECS" && exit 0

# Allow when the human approved a one-off quick edit in-conversation. This marker
# is written by the model ONLY after an explicit AskUserQuestion approval (see
# SKILL.md "Quick-mode"). It is short-lived and meant to be removed right after the
# edit — it is a convenience channel, not the hard bypass (that is the env var).
fresh "$adir/.quick-approved" "$QUICK_SECS" && exit 0

# Relaxed mode: note the missing plan but allow the edit (no block).
if [ "$SPEC_DRIVE" = "relaxed" ]; then
  echo "[hydraia] note: editing source before a frozen plan (spec-drive=relaxed). Consider /hydraia:feature." >&2
  exit 0
fi

# Otherwise (strict) block. Exit 2 tells Claude Code to reject the tool call and feed
# stderr back to the model, which can then recover via the pipeline or quick-mode.
cat >&2 <<EOF
[hydraia] BLOCKED: spec-drive gate.

You are editing source code before a frozen plan exists for this work.
Hydraia is spec-drive-design first — Phases 2 (spec + threat model) and 3
(plan + self-review) must complete before any code is written.

Recover with ONE of:
  • Run the pipeline: /hydraia:feature <what you are building>
    (or /hydraia:plan first to freeze the design, then execute).
  • Quick-mode (only if this change is genuinely trivial — no new logic, no new
    file, and it does NOT touch auth / PII / external input): ask the human via
    AskUserQuestion whether to skip the design ceremony (pro: far fewer tokens;
    con: no spec-drive record, no double review). If they approve, write the
    approval marker and retry, then run the real build/tests and remove it:
        printf 'reason\n' > "$adir/.quick-approved"
    Never write this marker without an explicit human "yes".
  • Human hard bypass (set by YOU in the shell, un-forgeable by the model):
        export HYDRAIA_ALLOW_DIRECT=1

Token cost or change size is NOT a reason for the model to skip — proportionality
is the human's call, made via one of the channels above, never the model's own.
EOF
exit 2
