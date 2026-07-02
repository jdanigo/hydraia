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
check_prereq node    "install Node.js >=18 from https://nodejs.org"
check_prereq npm     "ships with Node.js"
check_prereq python3 "install Python 3.8+ from https://python.org"
check_prereq pip     "python3 -m ensurepip --upgrade"
check_prereq git     "install git from https://git-scm.com"

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
