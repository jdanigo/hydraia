#!/usr/bin/env bash
# Hydraia run summary (Stop hook).
#
# Prints a real, transcript-derived summary at the end of a completed pipeline
# run: how many sub-agents were dispatched, which skills and models ran, and the
# token usage. Numbers come from the session transcript (message.usage /
# message.model / Skill+Task tool_use blocks) — never from the model
# self-reporting, which would hallucinate counts.
#
# The Stop hook fires at the end of EVERY assistant turn, so it must stay quiet
# unless a pipeline actually just finished. Phase 6 writes a one-shot marker
# (docs/hydraia/.run-complete); this hook emits ONLY when that marker is present,
# then removes it. No marker → silent exit.
#
# Accuracy note on sub-agents: the agent COUNT and the model list are always
# exact (dispatched agents are counted from Task tool_use blocks in the main
# transcript; models from every usage entry). Per-sub-agent token totals are
# included only insofar as Claude Code records sub-agent turns in this same
# transcript (sidechain entries) — if a CC version stores them elsewhere, the
# token figure reflects the parent session plus whatever sidechain turns are
# present. The count and model list do not depend on that.
#
# On any internal error this hook stays silent and exits 0 — a summary must
# never wedge the session.
set -uo pipefail

# --- Read the hook payload (Stop hook: transcript_path, cwd, ...) ------------
payload="$(cat 2>/dev/null || true)"

command -v python3 >/dev/null 2>&1 || exit 0

transcript_path=""
cwd=""
read -r transcript_path cwd < <(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print((d.get("transcript_path") or "") + "\t" + (d.get("cwd") or ""))
except Exception:
    print("\t")
' 2>/dev/null | awk -F'\t' '{print $1, $2}')

[ -n "$transcript_path" ] && [ -f "$transcript_path" ] || exit 0

# --- Resolve repo root and gate on the run-complete marker ------------------
base="${cwd:-$PWD}"
[ -d "$base" ] || base="$PWD"
repo="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0

marker="$repo/docs/hydraia/.run-complete"
[ -f "$marker" ] || exit 0        # no completed run this turn → stay silent
# The marker's first line selects verbosity: "detailed" → full breakdown, anything
# else (incl. empty / legacy "done") → the brief box. Phase 6 writes it per the
# human's plan-freeze choice.
DEPTH="$(head -n1 "$marker" 2>/dev/null | tr -d '[:space:]')"
case "$DEPTH" in detailed) DEPTH="detailed" ;; *) DEPTH="brief" ;; esac
rm -f "$marker" 2>/dev/null || true   # one-shot: consume it so we emit once

# --- Config: whether to print the summary and/or record telemetry -----------
# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true
RUN_SUMMARY="true"; TELEMETRY="true"
if command -v hy_config >/dev/null 2>&1; then
  RUN_SUMMARY="$(hy_config runSummary true)"
  TELEMETRY="$(hy_config telemetry true)"
fi
TELEM_FILE=""
if [ "$TELEMETRY" = "true" ]; then
  mkdir -p "${HOME}/.cache/hydraia" 2>/dev/null && TELEM_FILE="${HOME}/.cache/hydraia/telemetry.jsonl"
fi
NOW="$(date +%s)"

# --- Gather run-scoped context for the summary ------------------------------
# Sub-agent telemetry sidecar (written by agents.sh at each SubagentStop). It lives
# in the repo and accumulates across sessions/compaction, so it is the authoritative
# source for sub-agent model/token usage that the Stop-hook transcript cannot see.
SIDE="$repo/docs/hydraia/.agents/subagents.jsonl"

# Detailed mode enriches with "what shipped". Compute git facts here (the hook already
# has the repo) and the original request from the newest run log. Best-effort; empty
# on failure — never block the summary.
GITSTAT=""; REQUEST=""
if [ "$DEPTH" = "detailed" ]; then
  base="$(git -C "$repo" merge-base HEAD origin/main 2>/dev/null || git -C "$repo" merge-base HEAD main 2>/dev/null || true)"
  if [ -n "$base" ]; then
    GITSTAT="$(git -C "$repo" diff --shortstat "$base"..HEAD 2>/dev/null | sed 's/^ *//' || true)"
  fi
  newlog="$(ls -t "$repo"/docs/hydraia/runs/*.md 2>/dev/null | head -n1 || true)"
  if [ -n "$newlog" ] && [ -f "$newlog" ]; then
    REQUEST="$(grep -m1 -iE '^\s*(request|original request)\s*[:*-]' "$newlog" 2>/dev/null | sed -E 's/^[^:]*:\s*//; s/\*\*//g' | cut -c1-160 || true)"
  fi
fi

# --- Build the summary (and append telemetry) --------------------------------
summary="$(printf '%s' "$transcript_path" \
  | HY_REPO="$repo" HY_TELEM="$TELEM_FILE" HY_NOW="$NOW" HY_SIDE="$SIDE" \
    HY_DEPTH="$DEPTH" HY_GITSTAT="$GITSTAT" HY_REQUEST="$REQUEST" python3 -c '
import sys, json, os, glob

path  = sys.stdin.read().strip()
repo  = os.environ.get("HY_REPO", "")
telem = os.environ.get("HY_TELEM", "")
now   = os.environ.get("HY_NOW", "")
side  = os.environ.get("HY_SIDE", "")
depth = os.environ.get("HY_DEPTH", "brief")
gitstat = os.environ.get("HY_GITSTAT", "")
request = os.environ.get("HY_REQUEST", "")

def short(model):
    if not model or model == "<synthetic>":
        return None
    m = model
    if m.startswith("claude-"):
        m = m[len("claude-"):]
    parts = m.split("-")
    if parts and parts[-1].isdigit() and len(parts[-1]) >= 6:
        m = "-".join(parts[:-1])
    return m

def h(n):
    n = int(n)
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}k"
    return str(n)

def addmodel(d, sm, u):
    x = d.setdefault(sm, {"in": 0, "out": 0, "cr": 0, "cc": 0})
    x["in"]  += u.get("input_tokens", 0) or 0
    x["out"] += u.get("output_tokens", 0) or 0
    x["cr"]  += u.get("cache_read_input_tokens", 0) or 0
    x["cc"]  += u.get("cache_creation_input_tokens", 0) or 0

# --- Main session: sweep every transcript sharing this sessionId (survives file
# splits within the session), counting only non-sidechain turns. Dedup by uuid.
main_models = {}      # short -> usage
agents = {}           # subagent_type -> count (from Task blocks)
n_tasks = 0
skills = {}
sid = ""
try:
    with open(path) as fh:
        for line in fh:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("sessionId"):
                sid = o["sessionId"]; break
except Exception:
    pass

files = [path]
try:
    d = os.path.dirname(path)
    if d and sid:
        files = sorted(set([path] + glob.glob(os.path.join(d, "*.jsonl"))))
except Exception:
    files = [path]

seen = set()
for fp in files:
    try:
        fh = open(fp)
    except Exception:
        continue
    with fh:
        for line in fh:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if sid and o.get("sessionId") != sid:
                continue
            if o.get("isSidechain"):
                continue        # sub-agents come from the sidecar, not here
            uid = o.get("uuid")
            if uid:
                if uid in seen:
                    continue
                seen.add(uid)
            msg = o.get("message")
            if not isinstance(msg, dict):
                continue
            sm = short(msg.get("model"))
            u = msg.get("usage")
            if sm and isinstance(u, dict):
                addmodel(main_models, sm, u)
            content = msg.get("content")
            if isinstance(content, list):
                for b in content:
                    if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                        continue
                    if b.get("name") == "Task":
                        n_tasks += 1
                        st = (b.get("input") or {}).get("subagent_type") or "agent"
                        agents[st] = agents.get(st, 0) + 1
                    elif b.get("name") == "Skill":
                        sk = (b.get("input") or {}).get("skill") or ""
                        if sk:
                            sk = sk.split(":")[-1]
                            skills[sk] = skills.get(sk, 0) + 1

# --- Sub-agents: read the repo sidecar (authoritative for sub-agent usage). ---
sub_models = {}
n_sub = 0
if side:
    try:
        with open(side) as sf:
            for line in sf:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                n_sub += 1
                for sm, u in (rec.get("models") or {}).items():
                    x = sub_models.setdefault(sm, {"in": 0, "out": 0, "cr": 0, "cc": 0})
                    x["in"]  += u.get("in", 0) or 0
                    x["out"] += u.get("out", 0) or 0
                    x["cr"]  += u.get("cr", 0) or 0
                    x["cc"]  += u.get("cc", 0) or 0
    except Exception:
        pass

# Total agents dispatched: the sidecar (one record per finished sub-agent) is the
# reliable count; fall back to Task blocks if the sidecar is empty (e.g. sub-agents
# still counted but telemetry disabled).
n_agents = max(n_sub, n_tasks)

# Combined per-model view (main + sub) for totals and the dashboard.
combined = {}
for src in (main_models, sub_models):
    for sm, u in src.items():
        x = combined.setdefault(sm, {"in": 0, "out": 0, "cr": 0, "cc": 0})
        for k in ("in", "out", "cr", "cc"):
            x[k] += u[k]

if not combined:
    sys.exit(0)

def totals(d, k):
    return sum(v[k] for v in d.values())

tot_in  = totals(combined, "in")
tot_out = totals(combined, "out")
tot_cr  = totals(combined, "cr")
main_in, main_out = totals(main_models, "in"), totals(main_models, "out")
sub_in,  sub_out  = totals(sub_models, "in"),  totals(sub_models, "out")

# Persist one local telemetry record per completed run (never transmitted).
if telem:
    try:
        rec = {
            "ts": int(now) if now.isdigit() else 0,
            "repo": os.path.basename(repo) if repo else "",
            "agents": n_agents,
            "agentsByType": agents,
            "skills": skills,
            "models": {k: dict(v) for k, v in combined.items()},
            "main":   {"tokensIn": main_in, "tokensOut": main_out,
                       "models": {k: dict(v) for k, v in main_models.items()}},
            "subagents": {"count": n_sub, "tokensIn": sub_in, "tokensOut": sub_out,
                          "cacheRead": totals(sub_models, "cr"),
                          "models": {k: dict(v) for k, v in sub_models.items()}},
            "tokensIn": tot_in, "tokensOut": tot_out, "cacheRead": tot_cr,
        }
        with open(telem, "a") as tf:
            tf.write(json.dumps(rec) + "\n")
    except Exception:
        pass

# --- Render ------------------------------------------------------------------
model_names = ", ".join(sorted(combined))
if agents:
    breakdown = ", ".join(f"{c} {k}" for k, c in sorted(agents.items()))
    agent_line = f"{n_agents} dispatched ({breakdown})"
elif n_agents:
    agent_line = f"{n_agents} dispatched"
else:
    agent_line = "0 dispatched (main session only)"

lines = [
    "── Hydraia run summary ─────────────────",
    f"Models:  {model_names}",
    f"Agents:  {agent_line}",
    f"Tokens:  {h(tot_in)} in · {h(tot_out)} out · {h(tot_cr)} cache-read",
]
if skills:
    skill_items = sorted(skills.items(), key=lambda x: (-x[1], x[0]))
    if depth == "detailed":
        skill_list = ", ".join(f"{k}×{c}" if c > 1 else k for k, c in skill_items)
    else:
        skill_list = ", ".join(k for k, _ in skill_items)
    lines.append(f"Skills:  {skill_list}")

if depth == "detailed":
    if request:
        lines.append(f"Request: {request}")
    if gitstat:
        lines.append(f"Changed: {gitstat}")
    if main_models or sub_models:
        lines.append("Token split:")
        lines.append(f"         main:      {h(main_in)} in · {h(main_out)} out")
        lines.append(f"         sub-agents:{h(sub_in):>7} in · {h(sub_out)} out")
    # full per-model in/out/cache table
    for name in sorted(combined):
        d = combined[name]
        di, do, dc = h(d["in"]), h(d["out"]), h(d["cr"])
        lines.append(f"         ⤷ {name}: {di} in · {do} out · {dc} cache")
else:
    # per-model line only when more than one model ran (Opus/Sonnet split)
    if len(combined) > 1:
        for name in sorted(combined):
            d = combined[name]
            di, do = h(d["in"]), h(d["out"])
            lines.append(f"         ⤷ {name}: {di} in · {do} out")

lines.append("───────────────────────────────────────")
print("\n".join(lines))
' 2>/dev/null || true)"

[ -n "$summary" ] || exit 0

# Telemetry is recorded above regardless; only the on-screen summary is optional.
[ "$RUN_SUMMARY" = "true" ] || exit 0

# Surface to the user. systemMessage is the version-stable channel for a hook to
# show text; also echo to stderr so it appears in the transcript regardless.
printf '%s\n' "$summary" >&2
printf '%s' "$summary" | python3 -c '
import sys, json
print(json.dumps({"systemMessage": sys.stdin.read()}))
' 2>/dev/null || true

exit 0
