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
# Honors the codegraphAuto config toggle (dashboard-editable).
# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true
CODEGRAPH_AUTO="true"
command -v hy_config >/dev/null 2>&1 && CODEGRAPH_AUTO="$(hy_config codegraphAuto true)"
if [ "$CODEGRAPH_AUTO" = "true" ] && command -v codegraph >/dev/null 2>&1; then
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

# --- 3. Version-outdated nudge ---
# Warn (every session) when a newer Hydraia is published, and print the update
# commands. The network fetch is throttled to at most once a day with a short
# timeout, so it never slows a session start; offline or on any failure we stay
# silent and never block. The nudge is emitted every session — from the cached
# latest version — until the local plugin catches up.
LATEST_FILE="${CACHE_DIR}/latest-version"
LATEST_TS="${CACHE_DIR}/latest-version-check"
VERSION_URL="https://raw.githubusercontent.com/jdanigo/hydraia/main/.claude-plugin/plugin.json"

_hy_ver() { grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"\([0-9][^"]*\)".*/\1/'; }

local_ver=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]; then
  local_ver=$(_hy_ver < "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")
fi

# refresh the cached latest version at most once a day
lts=0
[ -f "$LATEST_TS" ] && lts=$(cat "$LATEST_TS" 2>/dev/null || echo 0)
if command -v curl >/dev/null 2>&1 && [ $(( now - lts )) -ge "$STALE_SECS" ]; then
  remote_ver=$(curl -fsSL --max-time 3 "$VERSION_URL" 2>/dev/null | _hy_ver)
  if [ -n "$remote_ver" ]; then
    printf '%s' "$remote_ver" > "$LATEST_FILE" 2>/dev/null || true
    echo "$now" > "$LATEST_TS" 2>/dev/null || true
  fi
fi

# compare local against the cached latest and nudge if older
latest_ver=""
[ -f "$LATEST_FILE" ] && latest_ver=$(cat "$LATEST_FILE" 2>/dev/null || echo "")
if [ -n "$local_ver" ] && [ -n "$latest_ver" ] && [ "$local_ver" != "$latest_ver" ]; then
  newest=$(printf '%s\n%s\n' "$local_ver" "$latest_ver" | sort -V | tail -1)
  if [ "$newest" = "$latest_ver" ]; then
    echo "[hydraia] update available: v${local_ver} → v${latest_ver}. Update with:" >&2
    echo "  claude plugin marketplace update hydraia" >&2
    echo "  claude plugin install hydraia" >&2
  fi
fi

exit 0
