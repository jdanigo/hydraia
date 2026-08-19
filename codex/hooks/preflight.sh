#!/usr/bin/env bash
# Codex SessionStart hook. Runs at session start. Emits NO stdout — Codex rejects
# any output it can't parse as its SessionStart schema ("invalid session start JSON
# output"), and additional-context injection is deferred until that schema is
# pinned. The pipeline context lives in the orchestrator skill instead. Keep this a
# clean no-op so the session starts without a hook failure.
set -euo pipefail
cat >/dev/null 2>&1 || true
exit 0
