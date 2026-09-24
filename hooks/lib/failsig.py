#!/usr/bin/env python3
"""Hydraia failure signature — shared by verifyloop.sh and baseline.sh.

Reduces a test/build log to the set of lines that describe *what* failed, with the
noise that changes run-to-run (timings, timestamps, addresses, temp paths, ANSI)
stripped, so the same failure produces the same signature across attempts.

Usage:
  failsig.py lines < log   -> normalized failure lines, sorted + unique, one per line
  failsig.py sig   < log   -> 12-hex signature of those lines (empty if no input)

Untrusted input: the log is only matched and hashed, never executed. Bounded to the
last 200 KB.
"""
import hashlib
import re
import sys

MAX_BYTES = 200 * 1024

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
DURATION = re.compile(r"\b\d+(?:\.\d+)?\s?(?:ms|s|sec|secs|seconds|m|min)\b", re.I)
CLOCK = re.compile(r"\b\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?\b")
ISODATE = re.compile(r"\b\d{4}-\d{2}-\d{2}[T ]?\S*")
HEX = re.compile(r"\b0x[0-9a-f]+\b", re.I)
TMP = re.compile(r"(?:/private)?/(?:tmp|var/folders)/\S+")
WS = re.compile(r"\s+")
FAILURE = re.compile(r"fail|error|✗|✕|×|panic|traceback|assert|exception|expected", re.I)
WRAPPER = re.compile(r"^error: exit code \d+$", re.I)
# Count / summary lines ("Tests 1 failed | 40 passed (41)", "=== 1 failed, 40 passed ===",
# "2 failing") change whenever a test is added or the command is narrowed — keeping them
# would make the same real failure look new (and break baseline matching).
SUMMARY = re.compile(
    r"^\W*(tests?|test files|test suites|suites?|specs?|examples?|ran)\b.*\d"
    r"|\b\d+\s+(failed|passed|failing|passing|skipped|pending|errors?|todo|tests?)\b",
    re.I)


def normalize(line):
    line = ANSI.sub("", line)
    line = TMP.sub("<tmp>", line)
    line = ISODATE.sub("<ts>", line)
    line = CLOCK.sub("<ts>", line)
    line = DURATION.sub("<dur>", line)
    line = HEX.sub("<hex>", line)
    return WS.sub(" ", line).strip()


def failure_lines(text):
    """Normalized lines that identify WHAT failed. Empty when the output carries no
    evidence beyond the harness's own "Error: Exit code N" wrapper — callers must then
    record nothing (every silent `exit 1` would otherwise share one signature)."""
    text = text[-MAX_BYTES:]
    norm = [normalize(l) for l in text.splitlines()]
    norm = [l for l in norm if l and not WRAPPER.match(l) and not SUMMARY.search(l)]
    hits = sorted({l for l in norm if FAILURE.search(l)})
    if hits:
        return hits
    return norm[-15:]


def signature(lines):
    if not lines:
        return ""
    return hashlib.sha1("\n".join(lines).encode("utf-8", "replace")).hexdigest()[:12]


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "sig"
    data = sys.stdin.buffer.read()[-MAX_BYTES:].decode("utf-8", "replace")
    lines = failure_lines(data)
    if mode == "lines":
        if lines:
            sys.stdout.write("\n".join(lines) + "\n")
    else:
        sys.stdout.write(signature(lines))


if __name__ == "__main__":
    main()
