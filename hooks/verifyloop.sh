#!/usr/bin/env bash
# Hydraia verify-loop breaker (PreToolUse + PostToolUse + PostToolUseFailure on Bash).
#
# The fix→test→fix loop is where current Opus models burn hours: the same failure comes
# back after fix after fix, or a failure that existed before the run gets "fixed". The
# review-cycle counter in agents.sh never sees this loop — it runs through Edit + Bash,
# not Task. This hook watches the verify commands themselves (tests/builds/lints):
#
#   - Every failed verify run is reduced to a failure SIGNATURE (hooks/lib/failsig.py:
#     the normalized failing lines, timings/paths/addresses stripped). Keyed on the
#     failure output, not the command, so rewording the command does not reset it.
#   - Same signature twice in a run  → NO PROGRESS feedback (stop patching symptoms).
#   - Same signature maxSameFailure times (default 3) → STALLED: further verify commands
#     are BLOCKED for this run until the HUMAN clears it. The run must end BLOCKED with
#     evidence instead of looping.
#   - A failure whose lines are all in the Phase-0 baseline (.baseline-failures) is
#     PRE-EXISTING: reported, never counted, never to be fixed by this run.
#   - Independently of any run: a verify command sent to the background without a
#     `timeout`/`gtimeout` wrapper is BLOCKED — a hung suite in the background has no
#     ceiling at all (a real run lost 14 minutes that way). Foreground calls are already
#     bounded by the Bash tool's own timeout.
#
# Payload facts (verified on Claude Code 2.1.x transcripts): a successful Bash call's
# tool_response is {stdout, stderr, interrupted, …} with no exit code; a failed one
# arrives as PostToolUseFailure with error "Error: Exit code N\n…". Both shapes, plus a
# string tool_response starting with "Error", are handled.
#
# PostToolUse cannot un-run a command: feedback is delivered with exit 2 + stderr, which
# Claude Code shows to the model. Human reset: rm <base>/.agents/verify.json, or
# HYDRAIA_ALLOW_DIRECT=1. Raise the ceiling: export HYDRAIA_MAX_SAME_FAILURE=4.
# On any internal error this hook ALLOWS (fail-open).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/config.sh" 2>/dev/null || true

[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

cwd="$(printf '%s' "$payload" | python3 -c '
import sys, json
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")
' 2>/dev/null || true)"
dir="${cwd:-$PWD}"; [ -d "$dir" ] || dir="$PWD"
repo="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0

# Opt-in + artifacts base (identical test to agents.sh).
hbase="$(cd "$repo" 2>/dev/null && hy_artifacts_dir)"
[ -n "$hbase" ] || hbase="$repo/docs/hydraia"
if [ ! -d "$hbase" ] \
   && [ -z "$(cd "$repo" 2>/dev/null && hy_repo_config artifactsDir "")" ] \
   && [ ! -d "$repo/docs/hydraia" ]; then
  exit 0
fi

MAXSAME="3"; PATTERN=""
if command -v hy_config >/dev/null 2>&1; then
  MAXSAME="$(cd "$repo" && hy_config maxSameFailure 3 HYDRAIA_MAX_SAME_FAILURE)"
  PATTERN="$(cd "$repo" && hy_config verifyPattern "" HYDRAIA_VERIFY_PATTERN)"
fi
case "$MAXSAME" in ''|*[!0-9]*) MAXSAME=3 ;; esac
[ "$MAXSAME" -lt 2 ] && MAXSAME=2

res="$(printf '%s' "$payload" | HY_BASE="$hbase" HY_MAX="$MAXSAME" HY_PAT="$PATTERN" \
  HY_LIB="$HERE/lib" python3 -c '
import json, os, re, sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, os.environ["HY_LIB"])
import failsig

FRESH = 43200
# A verify command is a segment (split on && || ; | newline) that STARTS with a test/build/
# lint runner — after optional env assignments, a timeout wrapper, a runner prefix, or a
# leading "(" / "cd dir &&". A tool name appearing mid-segment ("git commit -m bump pytest",
# "test -f jest.config.js", "rg vitest") is NOT a verify run.
DEFAULT = (r"^(?:\w+=\S*\s+)*(?:g?timeout\s+\S+\s+)?"
  r"(?:npx\s+|bunx\s+|pnpm\s+exec\s+|pnpm\s+dlx\s+|yarn\s+dlx\s+|poetry\s+run\s+|uv\s+run\s+|pipenv\s+run\s+)?("
  r"(npm|pnpm|yarn|bun)\s+(run\s+)?(test|build|lint|typecheck|type-check|check|e2e)\b"
  r"|(vitest|jest|pytest|tsc|eslint|rspec|phpunit|playwright)\b"
  r"|go\s+(test|build|vet)\b|cargo\s+(test|build|check|clippy)\b"
  r"|dotnet\s+(test|build)\b|mvn\b|gradle\b|\./gradlew\b|ng\s+(test|build)\b"
  r"|make\s+(test|check|build)\b|python3?\s+-m\s+(pytest|unittest)\b"
  r"|bash\s+\S*tests?/run\.sh)")
SEGMENT = re.compile(r"&&|\|\||;|\||\n")

def is_verify(cmd, rx):
    for seg in SEGMENT.split(cmd):
        seg = seg.strip().lstrip("( ").strip()
        if seg.startswith("cd ") or not seg:
            continue
        if rx.search(seg):
            return True
    return False

WATCH = re.compile(r"(^|\s)(--watch|-w|watch)(\s|$)")

def out(code, msg=""):
    # Line 1 = exit code; the rest = the message, raw (never re-interpreted by the shell).
    sys.stdout.write(str(code) + "\n" + msg + ("\n" if msg else ""))
    sys.exit(0)

try:
    d = json.load(sys.stdin)
except Exception:
    out(0)
if (d.get("tool_name") or "") != "Bash":
    out(0)
ti = d.get("tool_input") or {}
cmd = ti.get("command") or ""
try:
    verify = re.compile(os.environ.get("HY_PAT") or DEFAULT)
except re.error:
    verify = re.compile(DEFAULT)
if not is_verify(cmd, verify):
    out(0)

event = d.get("hook_event_name") or ""
base = os.environ["HY_BASE"]
mx = int(os.environ["HY_MAX"])
plan = os.path.join(base, ".active-plan")
state_p = os.path.join(base, ".agents", "verify.json")
now = time.time()
runid = ""
if os.path.isfile(plan) and now - os.path.getmtime(plan) < FRESH:
    runid = str(int(os.path.getmtime(plan)))

def load():
    try:
        s = json.load(open(state_p))
        if isinstance(s, dict) and s.get("runId") == runid:
            return s
    except Exception:
        pass
    return {"runId": runid, "sigs": {}, "stalled": None}

def save(s):
    try:
        os.makedirs(os.path.dirname(state_p), exist_ok=True)
        tmp = state_p + ".tmp"
        json.dump(s, open(tmp, "w"))
        os.replace(tmp, state_p)
    except Exception:
        pass

def stalled_msg(st):
    sample = "\n".join("    " + l for l in (st.get("sample") or [])[:5])
    return ("[hydraia] STALLED: verify loop is not converging.\n\n"
            "The same failure (signature " + st["sig"] + ") has come back " + str(st["n"]) +
            " times this run.\nMore patches will not fix a wrong hypothesis. STOP verifying and "
            "end the run BLOCKED,\nsurfacing to the human: the failing lines, each hypothesis "
            "tried, and what evidence\nwould settle it. Failing lines:\n" + sample + "\n\n"
            "Do NOT clear or edit Hydraia state files yourself — that is blocked and is the\n"
            "decision for the human. Tell the human the run is STALLED; they reset it after review.")

if event == "PreToolUse":
    if (ti.get("run_in_background") and not WATCH.search(cmd)
            and not re.search(r"(^|[\s;&|(])g?timeout\s+\S", cmd)):
        out(2, "[hydraia] BLOCKED: background verify command without a timeout.\n\n"
               "A test/build suite sent to the background has no ceiling — if one test hangs,\n"
               "the run waits forever. Run it in the FOREGROUND (the Bash tool timeout bounds it),\n"
               "or wrap it: timeout 600 <cmd>  (macOS: gtimeout from coreutils).\n"
               "Prefer the narrowest command that covers the files you changed.")
    if runid:
        s = load()
        if s.get("stalled"):
            out(2, stalled_msg(s["stalled"]))
    out(0)

if event not in ("PostToolUse", "PostToolUseFailure") or not runid:
    out(0)

failed, text = False, ""
tr = d.get("tool_response")
if event == "PostToolUseFailure":
    failed = True
    text = d.get("error") or ""
    if not text:
        text = tr if isinstance(tr, str) else json.dumps(tr or "")
elif isinstance(tr, str):
    if tr.lstrip().startswith("Error"):
        failed, text = True, tr
elif isinstance(tr, dict):
    code = None
    for k in ("exit_code", "exitCode", "returncode", "returnCode"):
        if tr.get(k) is not None:
            code = tr.get(k); break
    try:
        failed = code is not None and int(code) != 0
    except Exception:
        failed = False
    text = (tr.get("stdout") or "") + "\n" + (tr.get("stderr") or "")
if not failed:
    out(0)

lines = failsig.failure_lines(text)
sig = failsig.signature(lines)
if not sig:
    out(0)

bl_p = os.path.join(base, ".baseline-failures")
try:
    if now - os.path.getmtime(bl_p) < FRESH:
        bl = {l.rstrip("\n") for l in open(bl_p) if l.strip() and not l.startswith("#")}
        if lines and set(lines) <= bl:
            out(2, "[hydraia] note: PRE-EXISTING failure — every failing line is in the Phase-0 "
                   "baseline.\nIt was failing before this run touched anything. Do NOT fix it here "
                   "(the human\nalready decided how to handle it at Phase 0). Judge only failures "
                   "that are new.")
except OSError:
    pass

s = load()
n = int(s["sigs"].get(sig, 0)) + 1
s["sigs"][sig] = n
if n >= mx:
    s["stalled"] = {"sig": sig, "n": n, "sample": lines[:5]}
    save(s)
    out(2, stalled_msg(s["stalled"]))
save(s)
if n >= 2:
    out(2, "[hydraia] NO PROGRESS: this exact failure (signature " + sig + ") is back — seen " +
           str(n) + "x this run.\n\nThe last fix did not change the outcome. Stop patching "
           "symptoms. Before the next edit:\nstate ONE hypothesis for the root cause, gather "
           "evidence that confirms or kills it\n(read the code path, add a probe), and only then "
           "change code. If the spec itself is\nwrong, route it as bad_spec (revert + amend + "
           "re-derive), not another patch.\nAt " + str(mx) + "x verification is blocked for this run.")
out(0)
' 2>/dev/null || true)"

code="$(printf '%s\n' "$res" | sed -n '1p')"
case "$code" in
  2) printf '%s\n' "$res" | sed '1d' >&2; exit 2 ;;
  *) exit 0 ;;
esac
