#!/usr/bin/env bash
# Hydraia test baseline (Phase 0 helper — invoked by the orchestrator, not a hook).
#
#   bash "$CLAUDE_PLUGIN_ROOT/hooks/baseline.sh" -- <the project's test command…>
#
# Runs the project's test/build command ONCE, before any change, with a hard timeout,
# and records which failures already exist. verifyloop.sh reads that record so a
# pre-existing, flaky or hung failure is never attributed to (and "fixed" by) the run.
# Phase 0 shows the result to the human and ASKS what to do — never silently ignores.
#
# Output (stdout, exactly one BASELINE line first):
#   BASELINE: CLEAN
#   BASELINE: <N> pre-existing failure line(s)     (+ up to 20 of them)
#   BASELINE: TIMEOUT after <s>s                   (+ tail — a hung suite)
# Writes <artifacts-base>/.baseline-failures. Exit 0 (informational); 64 = usage error.
# Timeout: HYDRAIA_BASELINE_TIMEOUT seconds (default 600). Uses python subprocess so it
# works on macOS, which ships no `timeout` binary.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/config.sh" 2>/dev/null || true

[ "${1:-}" = "--" ] && shift
if [ "$#" -eq 0 ]; then
  echo "usage: baseline.sh -- <test command…>" >&2
  exit 64
fi
command -v python3 >/dev/null 2>&1 || { echo "BASELINE: SKIPPED (python3 missing)"; exit 0; }

repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
base=""
command -v hy_artifacts_dir >/dev/null 2>&1 && base="$(cd "$repo" && hy_artifacts_dir 2>/dev/null)"
[ -n "$base" ] || base="$repo/docs/hydraia"
mkdir -p "$base" 2>/dev/null || true
out="$base/.baseline-failures"
head_sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo NO_VCS)"
limit="${HYDRAIA_BASELINE_TIMEOUT:-600}"
case "$limit" in ''|*[!0-9]*) limit=600 ;; esac

HY_OUT="$out" HY_HEAD="$head_sha" HY_LIMIT="$limit" HY_SIG="$HERE/lib/failsig.py" \
python3 - "$@" <<'PY'
import os, signal, subprocess, sys, time
out, head, limit, sigpy = os.environ["HY_OUT"], os.environ["HY_HEAD"], int(os.environ["HY_LIMIT"]), os.environ["HY_SIG"]
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(sigpy))
import failsig
cmd = sys.argv[1:]
timed_out = False
try:
    # New session so a timeout kills the whole tree (test runners fork workers).
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        raw, _ = p.communicate(timeout=limit)
        code = p.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            p.kill()
        raw, _ = p.communicate()
        code = None
    text = (raw or b"").decode("utf-8", "replace")
except OSError as e:
    text, code = "error: cannot run command: %s" % e, 127
lines = [] if (code == 0 and not timed_out) else failsig.failure_lines(text)
with open(out, "w") as f:
    f.write("# head=%s ts=%d\n" % (head, int(time.time())))
    for l in lines:
        f.write(l + "\n")
if timed_out:
    print("BASELINE: TIMEOUT after %ds" % limit)
    for l in text.splitlines()[-15:]:
        print("  " + l)
elif code == 0:
    print("BASELINE: CLEAN")
else:
    print("BASELINE: %d pre-existing failure line(s)" % len(lines))
    for l in lines[:20]:
        print("  " + l)
PY
exit 0
