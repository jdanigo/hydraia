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

# --- Build the summary from the transcript (and append telemetry) ------------
summary="$(printf '%s' "$transcript_path" | HY_REPO="$repo" HY_TELEM="$TELEM_FILE" HY_NOW="$NOW" python3 -c '
import sys, json, os

path = sys.stdin.read().strip()
repo = os.environ.get("HY_REPO", "")
telem = os.environ.get("HY_TELEM", "")
now = os.environ.get("HY_NOW", "")

def short(model):
    if not model or model == "<synthetic>":
        return None
    m = model
    for pre in ("claude-",):
        if m.startswith(pre):
            m = m[len(pre):]
    # trim a trailing date stamp like -20251001
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

models = {}          # short name -> usage dict
agents = {}          # subagent_type -> count
n_agents = 0
skills = {}          # skill name (prefix-stripped) -> invocation count

with open(path) as fh:
    for line in fh:
        try:
            o = json.loads(line)
        except Exception:
            continue
        msg = o.get("message")
        if not isinstance(msg, dict):
            continue
        sm = short(msg.get("model"))
        u = msg.get("usage")
        if sm and isinstance(u, dict):
            d = models.setdefault(sm, {"in": 0, "out": 0, "cr": 0, "cc": 0})
            d["in"]  += u.get("input_tokens", 0) or 0
            d["out"] += u.get("output_tokens", 0) or 0
            d["cr"]  += u.get("cache_read_input_tokens", 0) or 0
            d["cc"]  += u.get("cache_creation_input_tokens", 0) or 0
        content = msg.get("content")
        if isinstance(content, list):
            for b in content:
                if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                    continue
                if b.get("name") == "Task":
                    n_agents += 1
                    st = (b.get("input") or {}).get("subagent_type") or "agent"
                    agents[st] = agents.get(st, 0) + 1
                elif b.get("name") == "Skill":
                    sk = (b.get("input") or {}).get("skill") or ""
                    if sk:
                        sk = sk.split(":")[-1]   # drop plugin prefix for display
                        skills[sk] = skills.get(sk, 0) + 1

if not models:
    sys.exit(0)

tot_in  = sum(d["in"]  for d in models.values())
tot_out = sum(d["out"] for d in models.values())
tot_cr  = sum(d["cr"]  for d in models.values())

# Persist one local telemetry record per completed run (never transmitted).
if telem:
    try:
        rec = {
            "ts": int(now) if now.isdigit() else 0,
            "repo": os.path.basename(repo) if repo else "",
            "agents": n_agents,
            "agentsByType": agents,
            "skills": skills,
            "models": {k: {"in": v["in"], "out": v["out"], "cr": v["cr"], "cc": v["cc"]}
                       for k, v in models.items()},
            "tokensIn": tot_in, "tokensOut": tot_out, "cacheRead": tot_cr,
        }
        with open(telem, "a") as tf:
            tf.write(json.dumps(rec) + "\n")
    except Exception:
        pass

model_names = ", ".join(sorted(models))
if agents:
    breakdown = ", ".join(f"{c} {k}" for k, c in sorted(agents.items()))
    agent_line = f"{n_agents} dispatched ({breakdown})"
else:
    agent_line = "0 dispatched (main session only)"

lines = [
    "── Hydraia run summary ─────────────────",
    f"Models:  {model_names}",
    f"Agents:  {agent_line}",
    f"Tokens:  {h(tot_in)} in · {h(tot_out)} out · {h(tot_cr)} cache-read",
]
if skills:
    skill_list = ", ".join(k for k, _ in sorted(skills.items(), key=lambda x: (-x[1], x[0])))
    lines.append(f"Skills:  {skill_list}")
# per-model line when more than one model ran (shows the Opus/Sonnet split)
if len(models) > 1:
    for name in sorted(models):
        d = models[name]
        di = h(d["in"])
        do = h(d["out"])
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
