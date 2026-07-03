#!/usr/bin/env bash
# Hydraia pre-flight (SessionStart): sync the code graph, and — at most once a
# day — nudge the user to run /hydraia:doctor if a managed binary is missing.
# Never installs anything, never blocks a session.
set -uo pipefail

CACHE_DIR="${HOME}/.cache/hydraia"
CACHE_FILE="${CACHE_DIR}/deps-check"
ROOT_FILE="${CACHE_DIR}/plugin-root"
STALE_SECS=86400
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- 0. Persist the plugin root ---
# CLAUDE_PLUGIN_ROOT is set for hook processes but NOT for the model's Bash tool, so
# the pipeline cannot locate doctor.sh on its own. Record it here (once per session)
# so Phase 0 can offer to install missing dependencies without the user running any
# command manually.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && printf '%s' "$CLAUDE_PLUGIN_ROOT" > "$ROOT_FILE" 2>/dev/null || true

# --- 1. Code graph bootstrap/sync ---
# First time in a project (no .codegraph/): `codegraph init` — it initializes AND
# builds the initial index, recursively covering every subfolder, so one init at the
# project root is enough (never init per-subfolder — that would scatter indexes).
# Afterwards: `codegraph sync` (fast, incremental). The initial index can be slow on
# a large repo, so run init in the BACKGROUND — session start must never block on it.
if command -v codegraph >/dev/null 2>&1; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if [ -d "$root/.codegraph" ]; then
    codegraph sync "$root" --quiet 2>/dev/null || true
  else
    # detach so a long initial index does not hold up the session
    ( nohup codegraph init "$root" >/dev/null 2>&1 & ) 2>/dev/null || true
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
