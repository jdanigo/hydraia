#!/usr/bin/env bash
# Install hydraia's Codex layer into the user's Codex config (user-level, dodging
# repo-local hook bug openai/codex#17532). Idempotent, non-destructive.
set -euo pipefail
HOME_DIR="${HOME}"; while [ $# -gt 0 ]; do case "$1" in --home) HOME_DIR="$2"; shift 2;; *) shift;; esac; done
SRC="$(cd "$(dirname "$0")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME_DIR/.codex}"
SKILLS_DIR="${HOME_SKILLS:-$HOME_DIR/.agents/skills}"
mkdir -p "$CODEX_HOME/hooks" "$SKILLS_DIR"
# hooks: expand $CODEX_HOME to the absolute path
sed "s|\$CODEX_HOME|$CODEX_HOME|g" "$SRC/hooks.json" > "$CODEX_HOME/hooks.json"
cp "$SRC/hooks/"*.sh "$CODEX_HOME/hooks/"; chmod +x "$CODEX_HOME/hooks/"*.sh
# config merge: root scalar keys MUST precede any [table] in TOML, so prepend them at
# the very top; append the [agents.*] role tables at the bottom. Sentinel makes it
# idempotent. (A pre-existing root `model` in the user's config is a documented edge —
# see SETUP.md; a fresh Codex config merges cleanly.)
CFG="$CODEX_HOME/config.toml"; touch "$CFG"
if ! grep -q 'sandbox_mode = "read-only"' "$CFG"; then
  TABLES_PART="$(awk 'f||/^\[agents\./{f=1; print}' "$SRC/config.sample.toml")"
  # Root scalar keys must precede any [table]. A pre-existing root sandbox_mode / model /
  # approval_policy would DUPLICATE on prepend → invalid TOML, or (last-wins) silently
  # downgrade the sandbox and defeat the gate. Detect that and refuse to touch root keys
  # — install only the agent tables (safe to append) and tell the user what to do.
  if grep -qE '^[[:space:]]*(sandbox_mode|model|approval_policy)[[:space:]]*=' "$CFG"; then
    echo "WARNING: $CFG already sets a root sandbox_mode/model/approval_policy." >&2
    echo "  Skipping the hydraia root-key merge to avoid duplicate TOML keys and a SILENT" >&2
    echo "  sandbox downgrade (which would defeat the write-gate)." >&2
    echo "  Set 'sandbox_mode = \"read-only\"' and 'approval_policy = \"on-request\"' yourself," >&2
    echo "  or move hydraia's keys into a [profiles.hydraia] table and run 'codex --profile hydraia'." >&2
    echo "  See codex/SETUP.md > Airtight write-gate." >&2
    { printf '\n# --- hydraia agents (added by codex/setup.sh) ---\n'; printf '%s\n' "$TABLES_PART"; } >> "$CFG"
  else
    ROOT_PART="$(awk '/^\[agents\./{exit} {print}' "$SRC/config.sample.toml")"
    tmp="$(mktemp)"
    { printf '# --- hydraia root (added by codex/setup.sh) ---\n'; printf '%s\n\n' "$ROOT_PART"; cat "$CFG"; } > "$tmp"
    { printf '\n# --- hydraia agents (added by codex/setup.sh) ---\n'; printf '%s\n' "$TABLES_PART"; } >> "$tmp"
    mv "$tmp" "$CFG"
  fi
fi
# skills
cp -R "$SRC/skills/"* "$SKILLS_DIR/"
echo "hydraia Codex layer installed."
echo "  hooks   : $CODEX_HOME/hooks.json"
echo "  agents  : [agents.*] roles in $CODEX_HOME/config.toml"
echo "  config  : $CODEX_HOME/config.toml (merged)"
echo "  skills  : $SKILLS_DIR/hydraia"
echo "Invoke in Codex with: \$hydraia <what to build>"
echo "Uninstall: remove the above, and the hydraia block from config.toml."
