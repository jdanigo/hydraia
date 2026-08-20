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
  ROOT_PART="$(awk '/^\[agents\./{exit} {print}' "$SRC/config.sample.toml")"
  TABLES_PART="$(awk 'f||/^\[agents\./{f=1; print}' "$SRC/config.sample.toml")"
  tmp="$(mktemp)"
  { printf '# --- hydraia root (added by codex/setup.sh) ---\n'; printf '%s\n\n' "$ROOT_PART"; cat "$CFG"; } > "$tmp"
  { printf '\n# --- hydraia agents (added by codex/setup.sh) ---\n'; printf '%s\n' "$TABLES_PART"; } >> "$tmp"
  mv "$tmp" "$CFG"
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
