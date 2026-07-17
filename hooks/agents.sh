#!/usr/bin/env bash
# Hydraia agent budget (PreToolUse on Task + SubagentStop).
#
# Bounds the blast radius of Phase 4: a plan with 135 tasks must NOT fan out into
# 135 concurrent sub-agents, each loading its own context — that is how a single
# run burns millions of tokens and blows a usage window. This hook makes the cap a
# runtime guarantee, not a prompt the model can rationalize past.
#
# Two limits, enforced only while a pipeline run is active (docs/hydraia/.active-plan
# fresh), only in repos that opt in (a docs/hydraia/ directory):
#
#   - TOTAL per run (HYDRAIA_MAX_AGENTS, default 30) — the HARD guarantee. Every
#     dispatch is counted under a lock, so even a same-turn burst of 135 Task calls
#     is serialized and cut off at the ceiling. Reliable on its own.
#   - CONCURRENT in flight (HYDRAIA_MAX_CONCURRENT, default 6) — best-effort throttle.
#     in_flight = dispatched - finished, where "finished" is counted from
#     SubagentStop. If that completion signal never arrives, the concurrency check
#     self-disables (never blocks on it) so the pipeline can never deadlock — the
#     TOTAL cap still bounds the run.
#
# Human override (never the model's call): raise a ceiling with an env var, e.g.
#     export HYDRAIA_MAX_AGENTS=50
#     export HYDRAIA_MAX_CONCURRENT=10
# HYDRAIA_ALLOW_DIRECT=1 lifts both caps entirely.
#
# On any internal error this hook ALLOWS (fail-open) — it must never wedge a run.
set -uo pipefail

# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true
if command -v hy_config >/dev/null 2>&1; then
  MAX_TOTAL="$(hy_config maxTotalAgents 30 HYDRAIA_MAX_AGENTS)"
  MAX_CONCURRENT="$(hy_config maxConcurrentAgents 6 HYDRAIA_MAX_CONCURRENT)"
else
  MAX_TOTAL="${HYDRAIA_MAX_AGENTS:-30}"
  MAX_CONCURRENT="${HYDRAIA_MAX_CONCURRENT:-6}"
fi
# Guard against a non-numeric config value.
case "$MAX_TOTAL" in ''|*[!0-9]*) MAX_TOTAL=30 ;; esac
case "$MAX_CONCURRENT" in ''|*[!0-9]*) MAX_CONCURRENT=6 ;; esac
FRESH_SECS=43200   # 12h — a stale .active-plan does not gate anything

payload="$(cat 2>/dev/null || true)"
command -v python3 >/dev/null 2>&1 || exit 0

# Parse event name, cwd, and tool name from the hook payload.
parsed="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print("\t".join([
        d.get("hook_event_name") or "",
        d.get("cwd") or "",
        d.get("tool_name") or "",
    ]))
except Exception:
    print("\t\t")
' 2>/dev/null || true)"
event="$(printf '%s' "$parsed" | awk -F'\t' '{print $1}')"
cwd="$(printf '%s' "$parsed" | awk -F'\t' '{print $2}')"
tool="$(printf '%s' "$parsed" | awk -F'\t' '{print $3}')"

# Resolve the repo and confirm Hydraia opt-in.
base="${cwd:-$PWD}"; [ -d "$base" ] || base="$PWD"
repo="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0

# Resolve the artifacts base (in-repo docs/hydraia, or the external dir chosen at the
# storage gate). Opt-in: base exists, OR repo registered in global config, OR legacy
# in-repo docs/hydraia/.
hbase="$(cd "$repo" 2>/dev/null && hy_artifacts_dir)"
[ -n "$hbase" ] || hbase="$repo/docs/hydraia"
if [ ! -d "$hbase" ] \
   && [ -z "$(cd "$repo" 2>/dev/null && hy_repo_config artifactsDir "")" ] \
   && [ ! -d "$repo/docs/hydraia" ]; then
  exit 0
fi

plan="$hbase/.active-plan"
adir="$hbase/.agents"
now="$(date +%s)"
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# Enforce only during an active run (Phase 3 armed the plan, Phase 6 disarms it).
[ -f "$plan" ] || exit 0
pm="$(mtime "$plan")"
[ $(( now - pm )) -lt "$FRESH_SECS" ] || exit 0

mkdir -p "$adir" 2>/dev/null || exit 0

# Reset per-run counters when a new run is detected (plan mtime changed).
reset_if_new_run() {
  local rid="$adir/runid" cur
  cur="$(cat "$rid" 2>/dev/null || echo)"
  if [ "$cur" != "$pm" ]; then
    : > "$adir/dispatched" 2>/dev/null || true
    : > "$adir/finished"   2>/dev/null || true
    printf '%s' "$pm" > "$rid" 2>/dev/null || true
  fi
}

# --- SubagentStop: record a completion, nothing to block ---------------------
# Sub-agent TOKEN/MODEL telemetry is NOT captured here: this hook does not fire
# reliably for every sub-agent (e.g. background dispatches), and Claude Code already
# persists each sub-agent's full transcript on disk at
# <project>/<sessionId>/subagents/agent-<id>.jsonl (+ .meta.json with its agentType).
# summary.sh reads that directory directly at run close — deterministic and
# hook-independent. Here we only bump the concurrency completion counter.
if [ "$event" = "SubagentStop" ]; then
  reset_if_new_run
  printf '1\n' >> "$adir/finished" 2>/dev/null || true
  exit 0
fi

# --- PreToolUse: only the Task tool is capped --------------------------------
[ "$tool" = "Task" ] || exit 0

# Human bypass lifts the caps.
[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0

# Acquire a portable lock (mkdir is atomic; macOS has no flock) so a same-turn
# burst of Task calls is serialized through the count-and-decide critical section.
lock="$adir/lock"
held=0
i=0
while [ "$i" -lt 400 ]; do
  if mkdir "$lock" 2>/dev/null; then held=1; break; fi
  # Steal only a genuinely dead lock. Guard on lm>0: under heavy parallel stat the
  # mtime probe can transiently return 0, and now-0 would look ancient and steal the
  # ACTIVE lock — the exact bug that let the cap leak. A real critical section here
  # is milliseconds, so 30s means the holder crashed.
  lm="$(mtime "$lock")"
  if [ "$lm" -gt 0 ] 2>/dev/null && [ $(( now - lm )) -ge 30 ]; then
    rmdir "$lock" 2>/dev/null || true
  fi
  i=$(( i + 1 ))
  sleep 0.03
done

# Could not serialize (heavy same-turn burst holding the lock). Fail CLOSED: never
# append without the lock — an unsynchronized count would let the cap leak. Tell the
# model to retry; a freed slot will let it through on the next wave.
if [ "$held" != 1 ]; then
  cat >&2 <<EOF
[hydraia] BLOCKED: agent budget — dispatch queue busy, could not reserve a slot.

Too many Task calls arrived at once. Re-dispatch this task after the in-flight
sub-agents make progress; do not fan out everything in a single turn.
EOF
  exit 2
fi
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

# Reset the counters (and the sub-agent telemetry sidecar) on a new run.
reset_if_new_run

disp="$(wc -l < "$adir/dispatched" 2>/dev/null | tr -d ' ')"; disp="${disp:-0}"
fin="$(wc -l < "$adir/finished" 2>/dev/null | tr -d ' ')";   fin="${fin:-0}"
inflight=$(( disp - fin )); [ "$inflight" -lt 0 ] && inflight=0

# Decide. TOTAL is the hard cap. CONCURRENT only applies once we have evidence the
# completion signal works (fin > 0) — otherwise it self-disables to avoid deadlock.
reason=""
if [ "$disp" -ge "$MAX_TOTAL" ]; then
  reason="total"
elif [ "$fin" -gt 0 ] && [ "$inflight" -ge "$MAX_CONCURRENT" ]; then
  reason="concurrent"
fi

if [ -n "$reason" ]; then
  # Do NOT count a rejected dispatch (it never runs, so no SubagentStop will ever
  # balance it) — that would poison the in-flight count.
  if [ "$reason" = "total" ]; then
    cat >&2 <<EOF
[hydraia] BLOCKED: agent budget — total cap reached ($disp/$MAX_TOTAL agents this run).

This run has already dispatched its maximum number of sub-agents. Firing more would
keep multiplying token cost. Do NOT keep retrying Task calls.

Recover by ONE of:
  • Consolidate the remaining plan tasks into fewer, larger tasks and finish the
    work with the agents already spent, or wrap up and move to Phase 5/6.
  • If this feature genuinely needs a bigger fleet, the HUMAN can raise the ceiling:
        export HYDRAIA_MAX_AGENTS=50
    (proportionality is the human's call, never the model's).
EOF
  else
    cat >&2 <<EOF
[hydraia] BLOCKED: agent budget — concurrency cap reached ($inflight in flight, max $MAX_CONCURRENT).

Too many sub-agents are running at once; each carries its own context and multiplies
token use. Dispatch work in WAVES: wait for in-flight agents to finish (their
SubagentStop frees a slot), then send the next batch of up to $MAX_CONCURRENT.
Re-dispatch this task after some of the current agents complete.

The HUMAN can widen the wave: export HYDRAIA_MAX_CONCURRENT=10
EOF
  fi
  exit 2
fi

# Allow: record the dispatch and let it run.
printf '1\n' >> "$adir/dispatched" 2>/dev/null || true
exit 0
