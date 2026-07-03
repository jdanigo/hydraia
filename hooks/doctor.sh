#!/usr/bin/env bash
# Hydraia doctor: validate prerequisites, install/update external binaries.
#   doctor.sh --check            read-only status, never mutates
#   doctor.sh --install [--yes]  install/update codegraph + markitdown
set -uo pipefail

CACHE_DIR="${HOME}/.cache/hydraia"
CACHE_FILE="${CACHE_DIR}/deps-check"
MODE="--check"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="--check" ;;
    --install) MODE="--install" ;;
    --yes|-y)  ASSUME_YES=1 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

echo "== Hydraia doctor (${MODE}) =="

# --- Prerequisites (never auto-installed) ---
echo "-- prerequisites --"
check_prereq() {
  local bin="$1" hint="$2"
  if have "$bin"; then
    echo "  ok   $bin"
  else
    echo "  MISS $bin — $hint"
  fi
}
# Per-OS, copy-paste install hints so the user never has to hunt for commands.
if [ "$(uname 2>/dev/null)" = "Darwin" ]; then
  H_NODE="brew install node"; H_PY="brew install python"; H_GIT="brew install git"
elif command -v apt-get >/dev/null 2>&1; then
  H_NODE="sudo apt-get install -y nodejs npm"; H_PY="sudo apt-get install -y python3 python3-pip"; H_GIT="sudo apt-get install -y git"
elif command -v dnf >/dev/null 2>&1; then
  H_NODE="sudo dnf install -y nodejs npm"; H_PY="sudo dnf install -y python3 python3-pip"; H_GIT="sudo dnf install -y git"
elif command -v winget >/dev/null 2>&1; then
  H_NODE="winget install OpenJS.NodeJS"; H_PY="winget install Python.Python.3.12"; H_GIT="winget install Git.Git"
else
  H_NODE="install Node.js >=18 from https://nodejs.org"; H_PY="install Python 3.8+ from https://python.org"; H_GIT="install git from https://git-scm.com"
fi
check_prereq node    "$H_NODE"
check_prereq npm     "ships with Node.js — $H_NODE"
check_prereq python3 "$H_PY"
check_prereq pip     "ships with Python — $H_PY (or: python3 -m ensurepip --upgrade)"
check_prereq git     "$H_GIT"

# --- Managed binaries ---
echo "-- managed binaries --"
codegraph_ok=0; have codegraph && codegraph_ok=1
markitdown_ok=0; have markitdown && markitdown_ok=1
echo "  codegraph:  $( [ $codegraph_ok -eq 1 ] && codegraph --version 2>/dev/null || echo 'not installed')"
echo "  markitdown: $( [ $markitdown_ok -eq 1 ] && markitdown --version 2>/dev/null || echo 'not installed')"

if [ "$MODE" = "--check" ]; then
  echo "-- discovery --"
  local_skills=$(find "$(dirname "$0")/../skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  local_agents=$(ls "$(dirname "$0")/../agents"/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "  skills: ${local_skills}  agents: ${local_agents}"
  echo "Run '/hydraia:doctor' to install or update anything marked not installed/outdated."
  exit 0
fi

# --- MODE=install ---
if [ "$ASSUME_YES" -ne 1 ]; then
  echo "This will run global npm/pip installs. Re-run with --yes to proceed."
  exit 0
fi

if have npm; then
  echo "Installing/updating codegraph to latest..."
  npm i -g @colbymchenry/codegraph@latest || echo "  codegraph install failed (non-fatal)"
else
  echo "Skipping codegraph: npm not found (install Node.js first)."
fi

if have pip; then
  if [ "$markitdown_ok" -eq 1 ]; then
    echo "Updating markitdown to latest..."
    pip install -U markitdown || echo "  markitdown update failed (non-fatal)"
  else
    echo "Installing markitdown..."
    pip install markitdown || echo "  markitdown install failed (non-fatal)"
  fi
else
  echo "Skipping markitdown: pip not found (install Python first)."
fi

mkdir -p "$CACHE_DIR"
date +%s > "$CACHE_FILE"
echo "Done. Cache stamped at ${CACHE_FILE}."
