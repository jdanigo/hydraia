#!/usr/bin/env bash
# Hydraia plan self-containment gate (PreToolUse on Bash).
#
# Fires when the model arms the spec-drive gate — i.e. writes a plan path into
# docs/hydraia/.active-plan. Before it lets the arm through, it scans that frozen
# plan's TASK bodies for "reference smells": phrasings that point the executor at
# the spec or another document for content it must produce ("follow spec §3",
# "see the design", "as in the spec"). Those break the pipeline's core promise —
# that ANY cheap, context-less executor (Haiku, Sonnet 5, Gemini Flash, Codex)
# can run a task from its block alone. A task that references external content is
# NOT self-contained: the cheap model can't see the spec, so it guesses, truncates,
# or gets creative. This gate turns "inline everything" from a prompt the planner
# might forget into a runtime block it cannot.
#
# It BLOCKS the arm only when ALL hold:
#   - the command writes to docs/hydraia/.active-plan, AND
#   - the human bypass is NOT set (HYDRAIA_ALLOW_DIRECT empty/unset), AND
#   - the referenced plan file exists and its task bodies contain a reference smell.
#
# On any internal error it ALLOWS (fail-open) — it must never wedge the pipeline.
set -uo pipefail

[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

cmd=""
if command -v python3 >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    print(ti.get("command") or "")
except Exception:
    print("")
' 2>/dev/null || true)"
fi
[ -n "$cmd" ] || exit 0

case "$cmd" in
  *docs/hydraia/.active-plan*) : ;;
  *) exit 0 ;;
esac

plan="$(printf '%s' "$cmd" | grep -oE 'docs/hydraia/plans/[^"'"'"' ]+\.md' | head -1 || true)"
[ -n "$plan" ] || exit 0
[ -f "$plan" ] || exit 0

smells="$(awk '/^### +Task/{t=1} t' "$plan" 2>/dev/null | grep -nEi \
  'follow (it|the skeleton|the above)|(see|per|refer to|copy from|copy the|as in|as described in|as defined in|as shown in) (the )?(spec|design)|the skeleton (in|from) the spec|§[0-9]|see (the )?design doc' \
  2>/dev/null || true)"

[ -z "$smells" ] && exit 0

cat >&2 <<EOF
[hydraia] BLOCKED: plan is not self-contained.

The plan you are freezing points the executor at the spec or another document for
content it must produce. A cheap, context-less executor (Haiku, Sonnet 5, Gemini
Flash, Codex) CANNOT see the spec — so it will guess, truncate, or get creative.
That is the exact failure this gate exists to prevent.

Offending task lines (relative to the first "### Task"):
$smells

Fix: INLINE the referenced content into the task itself — the full verbatim file
body, the exact code/skeleton, the literal old_string->new_string. Duplicate it out
of the spec even though it repeats: here DRY yields to self-containment, because the
task block must carry everything the weakest executor needs, with zero "go read X".

Then re-arm the gate. (Human hard bypass, if this is a false positive:
export HYDRAIA_ALLOW_DIRECT=1)
EOF
exit 2
