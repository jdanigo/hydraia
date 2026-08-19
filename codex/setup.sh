#!/usr/bin/env bash
# Install hydraia's Codex layer into the user's Codex config (user-level, dodging
# repo-local hook bug openai/codex#17532). Idempotent, non-destructive.
set -euo pipefail
HOME_DIR="${HOME}"; while [ $# -gt 0 ]; do case "$1" in --home) HOME_DIR="$2"; shift 2;; *) shift;; esac; done
SRC="$(cd "$(dirname "$0")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME_DIR/.codex}"
SKILLS_DIR="${HOME_SKILLS:-$HOME_DIR/.agents/skills}"
mkdir -p "$CODEX_HOME/hooks" "$CODEX_HOME/agents" "$SKILLS_DIR"
# hooks: expand $CODEX_HOME to the absolute path
sed "s|\$CODEX_HOME|$CODEX_HOME|g" "$SRC/hooks.json" > "$CODEX_HOME/hooks.json"
cp "$SRC/hooks/"*.sh "$CODEX_HOME/hooks/"; chmod +x "$CODEX_HOME/hooks/"*.sh
cp "$SRC/agents/"*.toml "$CODEX_HOME/agents/"
# config merge: append the sample block once
touch "$CODEX_HOME/config.toml"
if ! grep -q 'default_subagent_model = "gpt-5.6-luna"' "$CODEX_HOME/config.toml"; then
  { echo ""; echo "# --- hydraia (added by codex/setup.sh) ---"; cat "$SRC/config.sample.toml"; } >> "$CODEX_HOME/config.toml"
fi
# skills
cp -R "$SRC/skills/"* "$SKILLS_DIR/"
echo "hydraia Codex layer installed."
echo "  hooks   : $CODEX_HOME/hooks.json"
echo "  agents  : $CODEX_HOME/agents/"
echo "  config  : $CODEX_HOME/config.toml (merged)"
echo "  skills  : $SKILLS_DIR/hydraia"
echo "Invoke in Codex with: \$hydraia <what to build>"
echo "Uninstall: remove the above, and the hydraia block from config.toml."
