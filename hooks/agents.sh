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
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# The sub-agent tool is "Agent" on current Claude Code ("Task" on older builds). Matching
# only "Task" silently disabled every cap below — accept both.
is_dispatch=0
case "$tool" in Task|Agent) is_dispatch=1 ;; esac

# Extract subagent_type (namespace-stripped: "hydraia:hydraia-reviewer" → "hydraia-reviewer"),
# the explicit model, and the description from the dispatch payload.
brk="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin); ti = d.get("tool_input") or {}
    clean = lambda v: " ".join(str(v or "").split())   # no tabs/newlines: one record, 3 fields
    print("\t".join([clean(ti.get("subagent_type")), clean(ti.get("model")),
                     clean(ti.get("description"))]))
except Exception:
    print("\t\t")
' 2>/dev/null || true)"
sub_type="$(printf '%s' "$brk" | awk -F'\t' '{print $1}')"
sub_model="$(printf '%s' "$brk" | awk -F'\t' '{print $2}')"
sub_desc="$(printf '%s' "$brk" | awk -F'\t' '{print $3}')"
sub_base="${sub_type##*:}"

# --- Opus gate: Opus only judges (independent of an active run) ----------------------
# Policy: the orchestrator session + the judge reviewers run on Opus; everything else runs
# on Sonnet (or Haiku). A dispatch is "effective Opus" when it names an opus model, or when
# it is an unpinned generic agent with no model (it silently inherits the parent's Opus).
# Executors may run on Opus only when the human chose the Max-quality routing at Phase 3
# (recorded in <base>/.agents/routing). Human bypass: HYDRAIA_ALLOW_OPUS=1.
if [ "$event" = "PreToolUse" ] && [ "$is_dispatch" = 1 ] \
   && [ -z "${HYDRAIA_ALLOW_DIRECT:-}" ] && [ -z "${HYDRAIA_ALLOW_OPUS:-}" ]; then
  OPUS_GATE="strict"; command -v hy_config >/dev/null 2>&1 && OPUS_GATE="$(cd "$repo" && hy_config opusGate strict HYDRAIA_OPUS_GATE)"
  if [ "$OPUS_GATE" != "off" ]; then
    eff_opus=0
    case "$sub_model" in *opus*|*Opus*) eff_opus=1 ;; esac
    if [ -z "$sub_model" ]; then
      case "$sub_base" in ''|general-purpose|Explore|Plan|claude) eff_opus=1 ;; esac
    fi
    if [ "$eff_opus" = 1 ]; then
      allowed=0
      case "$sub_base" in hydraia-reviewer|security-reviewer) allowed=1 ;; esac
      if [ "$allowed" = 0 ]; then
        case "$sub_base" in
          hydraia-executor|qa-automation)
            rf="$adir/routing"
            if [ -f "$rf" ] && [ $(( now - $(mtime "$rf") )) -lt "$FRESH_SECS" ] \
               && [ "$(head -1 "$rf" 2>/dev/null | tr -d '[:space:]')" = "max-quality" ]; then
              allowed=1
            fi ;;
        esac
      fi
      if [ "$allowed" = 0 ]; then
        if [ "$OPUS_GATE" = "warn" ]; then
          echo "[hydraia] note: '${sub_type:-general-purpose}' is dispatching on Opus (policy: Opus only judges)." >&2
        else
          # Build the reason outside the heredoc: an apostrophe inside ${var:-…} in an
          # unquoted heredoc is a "bad substitution" on macOS bash 3.2.
          if [ -n "$sub_model" ]; then why="it asked for model \"$sub_model\""
          else why="it has no model pin, so it would inherit the session model (Opus)"; fi
          cat >&2 <<EOF
[hydraia] BLOCKED: Opus gate — '${sub_type:-general-purpose}' would run on Opus.

Policy: Opus is the orchestrator and the judge (hydraia-reviewer, security-reviewer).
Every other agent runs on Sonnet — $why.
Re-dispatch with model: "sonnet" (or "haiku" for mechanical work).
Executors run on Opus only when the human picked Max quality at Phase 3.
Human override: export HYDRAIA_ALLOW_OPUS=1  (or opusGate=warn|off in config).
EOF
          exit 2
        fi
      fi
    fi
  fi
fi

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
    : > "$adir/ledger.json" 2>/dev/null || true
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

# --- PreToolUse: only the sub-agent tool (Agent / legacy Task) is capped -------
[ "$is_dispatch" = 1 ] || exit 0

# Human bypass lifts the caps.
[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0

# --- Kill switch + token caps ------------------------------------------------
# Kill switch: config loopPause or env HYDRAIA_PAUSE blocks ALL dispatch immediately.
PAUSED="false"; command -v hy_config >/dev/null 2>&1 && PAUSED="$(hy_config loopPause false HYDRAIA_PAUSE)"
if [ "$PAUSED" = "true" ] || [ -n "${HYDRAIA_PAUSE:-}" ]; then
  cat >&2 <<EOF
[hydraia] BLOCKED: loop paused (kill switch).

Sub-agent dispatch is disabled (loopPause / HYDRAIA_PAUSE). Switch to report-only.
Clear the pause to resume: unset HYDRAIA_PAUSE (or set loopPause=false in config).
EOF
  exit 2
fi

# Token caps (default 0 = off). Sum today's spend from the telemetry summary.sh writes.
DAILY_CAP="$(hy_config dailyTokenCap 0 HYDRAIA_DAILY_TOKEN_CAP 2>/dev/null || echo 0)"
RUN_CAP="$(hy_config perRunTokenCap 0 HYDRAIA_RUN_TOKEN_CAP 2>/dev/null || echo 0)"
case "$DAILY_CAP" in ''|*[!0-9]*) DAILY_CAP=0 ;; esac
case "$RUN_CAP" in ''|*[!0-9]*) RUN_CAP=0 ;; esac
TELEM="${HOME}/.cache/hydraia/telemetry.jsonl"
if { [ "$DAILY_CAP" -gt 0 ] || [ "$RUN_CAP" -gt 0 ]; } && [ -f "$TELEM" ]; then
  over="$(HY_T="$TELEM" HY_NOW="$now" HY_DC="$DAILY_CAP" HY_RC="$RUN_CAP" HY_RS="$pm" python3 -c '
import os
t=os.environ["HY_T"]; now=int(os.environ["HY_NOW"]); dc=int(os.environ["HY_DC"]); rc=int(os.environ["HY_RC"]); rs=int(os.environ.get("HY_RS") or 0)
import json
day=0; run=0
try:
    for line in open(t):
        try: r=json.loads(line)
        except Exception: continue
        ts=int(r.get("ts") or 0); tok=int(r.get("tokensIn") or 0)+int(r.get("tokensOut") or 0)
        if now-ts <= 86400: day+=tok
        if rs and ts>=rs: run+=tok
    if dc and day>=dc: print("daily "+str(day)+"/"+str(dc))
    elif rc and run>=rc: print("run "+str(run)+"/"+str(rc))
    else: print("")
except Exception:
    print("")
' 2>/dev/null || true)"
  if [ -n "$over" ]; then
    scope="${over%% *}"; nums="${over#* }"
    cat >&2 <<EOF
[hydraia] BLOCKED: token budget — ${scope} cap reached (${nums} tokens).

New sub-agent dispatch would exceed the configured ${scope} token cap. Switch to
report-only and surface where the run stands. The HUMAN raises the ceiling if warranted:
  export HYDRAIA_DAILY_TOKEN_CAP=…   (or HYDRAIA_RUN_TOKEN_CAP=…)
EOF
    exit 2
  fi
fi

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

# --- Circuit breaker: per-item attempt ledger --------------------------------
# Count executor attempts per task-slug and reviewer cycles per run. Block past the
# caps and tell the orchestrator to escalate, mechanizing the Phase 4/5 soft caps.
MAX_RETRIES="$(hy_config maxTaskRetries 2 HYDRAIA_MAX_TASK_RETRIES 2>/dev/null || echo 2)"
MAX_REVIEW="$(hy_config maxReviewCycles 2 HYDRAIA_MAX_REVIEW_CYCLES 2>/dev/null || echo 2)"
MAX_FIX="$(hy_config maxFixAttempts 2 HYDRAIA_MAX_FIX_ATTEMPTS 2>/dev/null || echo 2)"
MAX_FIX_RUN="$(hy_config maxFixDispatches 6 HYDRAIA_MAX_FIX_DISPATCHES 2>/dev/null || echo 6)"
case "$MAX_RETRIES" in ''|*[!0-9]*) MAX_RETRIES=2 ;; esac
case "$MAX_REVIEW" in ''|*[!0-9]*) MAX_REVIEW=2 ;; esac
case "$MAX_FIX" in ''|*[!0-9]*) MAX_FIX=2 ;; esac
case "$MAX_FIX_RUN" in ''|*[!0-9]*) MAX_FIX_RUN=6 ;; esac
ledger="$adir/ledger.json"

# Role classifier — four buckets (subagent_type is namespace-stripped in $sub_base):
#   fix     → a Phase 5/6 fix dispatch, tagged [fix:<slug>] in its description. Counted per
#             slug (maxFixAttempts) AND per run (maxFixDispatches): the fix loop is finite.
#             Checked first — a fix runs on the executor agent type.
#   review  → ONLY the whole-branch Pass-1 reviewer (hydraia-reviewer), dispatched once
#             per review cycle. It alone is cycle-counted against maxReviewCycles.
#   exempt  → every other reviewer / analysis fan-out agent. Phase 5 fires several reviewers
#             in the FIRST pass; they run once per pass and are already bounded by the
#             total/concurrent agent caps, so they must NEVER be review-cycle-counted.
#   task    → executor, keyed by its [task:<slug>] tag (fallback: hash of the description).
# Order matters: hydraia-reviewer MUST match before the generic *reviewer* exempt pattern.
fix_slug="$(printf '%s' "$sub_desc" | grep -oE '\[fix:[^]]+\]' | head -1 | sed 's/\[fix:\(.*\)\]/\1/' || true)"
if [ -n "$fix_slug" ]; then
  role="fix"
else
  case "$sub_base" in
    hydraia-reviewer) role="review" ;;
    *reviewer*|*review*|silent-failure-hunter|security-scan|type-design-analyzer|*-analyzer|database-*) role="exempt" ;;
    *) role="task" ;;
  esac
fi

ledger_n() { # ledger_n <key> → current count (corrupt/missing ledger → 0, fail-open)
  HY_L="$ledger" HY_K="$1" python3 -c '
import os, json
try:
    d = json.load(open(os.environ["HY_L"]))
    print(int((d.get("items") or {}).get(os.environ["HY_K"], {}).get("n", 0)))
except Exception:
    print(0)
' 2>/dev/null || echo 0
}

# Breaker decision + increment apply only to fix/review/task roles. An exempt role skips the
# key/cap resolution, the cur>=cap block, and the increment entirely, falling straight
# through to the total/concurrent cap logic below (never counted, never review-blocked).
key2=""
if [ "$role" != "exempt" ]; then
  if [ "$role" = "fix" ]; then
    key="fix:$fix_slug"; cap="$MAX_FIX"; key2="fix:run"
    runfix="$(ledger_n "fix:run")"; case "$runfix" in ''|*[!0-9]*) runfix=0 ;; esac
    if [ "$runfix" -ge "$MAX_FIX_RUN" ]; then
      cat >&2 <<EOF
[hydraia] BLOCKED: circuit breaker — fix budget for this run exhausted ($runfix/$MAX_FIX_RUN fix dispatches).

The review/verify → fix loop has used its whole budget. Do NOT dispatch another fix.
End the run BLOCKED and surface to the human: the findings still open, what each fix
tried, and the evidence. Raise the ceiling only if the human decides:
  export HYDRAIA_MAX_FIX_DISPATCHES=10
EOF
      exit 2
    fi
  elif [ "$role" = "review" ]; then
    key="review:run"; cap="$MAX_REVIEW"
  else
    slug="$(printf '%s' "$sub_desc" | grep -oE '\[task:[^]]+\]' | head -1 | sed 's/\[task:\(.*\)\]/\1/' || true)"
    [ -n "$slug" ] || slug="h$(printf '%s' "$sub_desc" | cksum | awk '{print $1}')"
    key="task:$slug"; cap="$MAX_RETRIES"
  fi

  # Read the current count for key and decide — under the lock already held.
  cur="$(ledger_n "$key")"
  case "$cur" in ''|*[!0-9]*) cur=0 ;; esac

  if [ "$cur" -ge "$cap" ]; then
    if [ "$role" = "fix" ]; then
      cat >&2 <<EOF
[hydraia] BLOCKED: circuit breaker — fix "$fix_slug" exhausted its attempts ($cur/$cap).

This finding has been "fixed" $cur times and is still open — the hypothesis is wrong or
the spec is. Do NOT dispatch it again. Route it as bad_spec (revert + amend the spec +
re-derive) if the spec caused it; otherwise end the run BLOCKED with the evidence.
Raise the ceiling only if the human decides: export HYDRAIA_MAX_FIX_ATTEMPTS=3
EOF
      exit 2
    elif [ "$role" = "review" ]; then
      cat >&2 <<EOF
[hydraia] BLOCKED: circuit breaker — review cycles exhausted ($cur/$cap this run).

The review→fix loop has run its allotted cycles without converging. Do NOT dispatch
another review pass. STOP and surface the remaining findings to the human with the
evidence (which findings persist, what was tried). Raise the ceiling only if the human
decides: export HYDRAIA_MAX_REVIEW_CYCLES=3
EOF
    else
      cat >&2 <<EOF
[hydraia] BLOCKED: circuit breaker — task "$slug" exhausted its attempts ($cur/$cap).

This task has been retried its maximum times without landing. Do NOT re-dispatch it.
STOP and surface it as a genuine BLOCKER to the human with the evidence (no commit,
attempt count). Raise the ceiling only if the human decides:
  export HYDRAIA_MAX_TASK_RETRIES=3
EOF
    fi
    exit 2
  fi
fi

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

# Allow (final path): the total/concurrent cap has passed, so this dispatch will run.
# Only NOW increment the breaker ledger for review/task roles — a dispatch blocked by the
# breaker or the total/concurrent cap above must never burn a breaker attempt. Exempt
# roles are never counted. Still under the held lock.
if [ "$role" != "exempt" ]; then
  HY_L="$ledger" HY_K="$key" HY_K2="$key2" HY_RID="$pm" python3 -c '
import os, json
p=os.environ["HY_L"]
try: d=json.load(open(p))
except Exception: d={}
if not isinstance(d,dict): d={}
d["runId"]=os.environ["HY_RID"]
items=d.setdefault("items",{})
for k in (os.environ["HY_K"], os.environ.get("HY_K2") or ""):
    if not k: continue
    it=items.setdefault(k,{"n":0})
    it["n"]=int(it.get("n",0))+1
tmp=p+".tmp"
json.dump(d,open(tmp,"w"))
os.replace(tmp,p)
' 2>/dev/null || true
fi

# Record the dispatch and let it run.
printf '1\n' >> "$adir/dispatched" 2>/dev/null || true
exit 0
