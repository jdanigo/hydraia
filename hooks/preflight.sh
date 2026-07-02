#!/usr/bin/env bash
# Hydraia pre-flight (SessionStart): sync the code graph, and — at most once a
# day — nudge the user to run /hydraia:doctor if a managed binary is missing.
# Never installs anything, never blocks a session.
set -uo pipefail

CACHE_DIR="${HOME}/.cache/hydraia"
CACHE_FILE="${CACHE_DIR}/deps-check"
STALE_SECS=86400

# --- 1. Code graph sync (belt-and-suspenders; daemon usually handles it) ---
if command -v codegraph >/dev/null 2>&1; then
  if codegraph status >/dev/null 2>&1; then
    codegraph sync . --quiet 2>/dev/null || true
  else
    codegraph index . --quiet 2>/dev/null || true
  fi
fi

# --- 2. Daily, non-invasive dependency nudge ---
now=$(date +%s)
last=0
[ -f "$CACHE_FILE" ] && last=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)
if [ $(( now - last )) -ge "$STALE_SECS" ]; then
  need_doctor=0
  command -v codegraph  >/dev/null 2>&1 || need_doctor=1
  command -v markitdown >/dev/null 2>&1 || need_doctor=1
  if [ "$need_doctor" -eq 1 ]; then
    echo "[hydraia] some dependencies are missing — run /hydraia:doctor to install/update them." >&2
  fi
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  echo "$now" > "$CACHE_FILE" 2>/dev/null || true
fi

exit 0
