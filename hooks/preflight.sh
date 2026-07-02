#!/usr/bin/env bash
# Hydraia pre-flight: ensure the code graph exists and is fresh before any work.
# codegraph auto-syncs on save via its daemon; this is the belt-and-suspenders
# pass for the start of a session (or when the daemon is disabled).
set -euo pipefail

if command -v codegraph >/dev/null 2>&1; then
  # Incremental sync is cheap; full index only if no graph exists yet.
  if codegraph status >/dev/null 2>&1; then
    codegraph sync . --quiet 2>/dev/null || true
  else
    codegraph index . --quiet 2>/dev/null || true
  fi
else
  echo "[hydraia] codegraph not found on PATH — install it to enable graph context:" >&2
  echo "[hydraia]   npm i -g @colbymchenry/codegraph@latest" >&2
fi
