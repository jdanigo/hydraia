#!/usr/bin/env bash
# Hydraia doctor: validate prerequisites, install/update external binaries.
#   doctor.sh --check                read-only status, never mutates
#   doctor.sh --install [--yes]      install/update codegraph + markitdown
#   doctor.sh --install-e2e [--yes]  install E2E browser binaries (Playwright/Cypress)
set -uo pipefail

CACHE_DIR="${HOME}/.cache/hydraia"
CACHE_FILE="${CACHE_DIR}/deps-check"
MODE="--check"
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check)       MODE="--check" ;;
    --install)     MODE="--install" ;;
    --install-e2e) MODE="--install-e2e" ;;
    --yes|-y)      ASSUME_YES=1 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a usable Python >=3.8 across platforms: python3, python, or the Windows
# 'py' launcher (which needs '-3'). Sets PYTHON to the invocation (may be "py -3").
PYTHON=""
pick_python() {
  local c
  for c in python3 python; do
    if have "$c" && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
      PYTHON="$c"; return 0
    fi
  done
  if have py && py -3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
    PYTHON="py -3"; return 0
  fi
  return 1
}

# A tool counts as present if it resolves on PATH OR sits in a known user bin dir
# (pipx / npm-global / pip --user land here; they join PATH in a fresh shell — and
# Hydraia deps apply next session anyway, so that is success, not failure).
user_bindirs() {
  # ${VAR:-} guards against 'set -u' when APPDATA (Windows-only) is unset.
  printf '%s\n' \
    "${HOME:-}/.local/bin" \
    "${HOME:-}/.npm-global/bin" \
    "${HOME:-}/Library/Python"/*/bin \
    "${APPDATA:-}/Python"/*/Scripts \
    "${HOME:-}/AppData/Roaming/Python"/*/Scripts 2>/dev/null
}
resolves() { have "$1"; }
installed_anywhere() {
  have "$1" && return 0
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && { [ -x "$d/$1" ] || [ -x "$d/$1.exe" ]; } && return 0
  done <<EOF
$(user_bindirs)
EOF
  return 1
}

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
# Python/pip: accept python3, python, or the Windows 'py' launcher, and 'python -m pip'.
if pick_python; then
  echo "  ok   python ($PYTHON)"
  if $PYTHON -m pip --version >/dev/null 2>&1; then
    echo "  ok   pip ($PYTHON -m pip)"
  else
    echo "  MISS pip — $PYTHON -m ensurepip --upgrade"
  fi
else
  echo "  MISS python — $H_PY"
  echo "  MISS pip — $H_PY"
fi
check_prereq git     "$H_GIT"

# --- Managed binaries ---
echo "-- managed binaries --"
codegraph_ok=0; have codegraph && codegraph_ok=1
markitdown_ok=0; have markitdown && markitdown_ok=1
echo "  codegraph:  $( [ $codegraph_ok -eq 1 ] && codegraph --version 2>/dev/null || echo 'not installed')"
echo "  markitdown: $( [ $markitdown_ok -eq 1 ] && markitdown --version 2>/dev/null || echo 'not installed')"

# --- E2E browser binaries (opt-in, project-scoped: only relevant if the repo
# already decided on a framework via its own config file) ---
detect_e2e_framework() {
  if ls playwright.config.* >/dev/null 2>&1; then echo "playwright"
  elif ls cypress.config.* >/dev/null 2>&1; then echo "cypress"
  elif grep -q '"@playwright/test"' package.json 2>/dev/null; then echo "playwright"
  elif grep -q '"cypress"' package.json 2>/dev/null; then echo "cypress"
  else echo "none"
  fi
}
# Cache dirs Playwright/Cypress download browser binaries into — existence of
# any versioned subdir means at least one browser is already cached.
playwright_browsers_cached() {
  local d
  for d in "${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright" "$HOME/Library/Caches/ms-playwright"; do
    [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ] && return 0
  done
  return 1
}
cypress_binary_cached() {
  local d
  for d in "${XDG_CACHE_HOME:-$HOME/.cache}/Cypress" "$HOME/Library/Caches/Cypress"; do
    [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ] && return 0
  done
  return 1
}
E2E_FRAMEWORK="$(detect_e2e_framework)"
if [ "$E2E_FRAMEWORK" != "none" ]; then
  echo "  e2e framework: $E2E_FRAMEWORK (detected)"
  if [ "$E2E_FRAMEWORK" = "playwright" ]; then
    playwright_browsers_cached && echo "  e2e browsers:  cached" || echo "  e2e browsers:  not installed — run '/hydraia:doctor' e2e install (see below)"
  else
    cypress_binary_cached && echo "  e2e browsers:  cached" || echo "  e2e browsers:  not installed — run '/hydraia:doctor' e2e install (see below)"
  fi
else
  echo "  e2e framework: none detected (no playwright.config.*/cypress.config.* in this repo)"
fi

if [ "$MODE" = "--check" ]; then
  echo "-- discovery --"
  local_skills=$(find "$(dirname "$0")/../skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  local_agents=$(ls "$(dirname "$0")/../agents"/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "  skills: ${local_skills}  agents: ${local_agents}"
  echo "Run '/hydraia:doctor' to install or update anything marked not installed/outdated."
  exit 0
fi

# --- MODE=install-e2e (Playwright/Cypress browser binaries — opt-in, heavy) ---
if [ "$MODE" = "--install-e2e" ]; then
  if [ "$E2E_FRAMEWORK" = "none" ]; then
    echo "No E2E framework detected (no playwright.config.*/cypress.config.* and no"
    echo "@playwright/test or cypress in package.json) — nothing to install here."
    echo "Choosing a framework is a plan-level decision, not this installer's."
    exit 0
  fi
  if [ "$ASSUME_YES" -ne 1 ]; then
    echo "This will download the ${E2E_FRAMEWORK} browser binary via npx (one-time,"
    echo "roughly 100-300MB), no sudo. Re-run with --yes to proceed."
    exit 0
  fi
  mkdir -p "$CACHE_DIR" 2>/dev/null || true

  # Browser binary only (no system libraries) — never needs sudo, works the same
  # on macOS, Linux, and Windows-via-WSL.
  install_playwright_browsers() {
    if ! have npx; then
      echo "  skip playwright browsers: npx not found — $H_NODE"
      return
    fi
    echo "Installing Playwright browser binaries (chromium)…"
    local err="${CACHE_DIR}/playwright-err.log"
    if npx --yes playwright install chromium >/dev/null 2>"$err"; then
      return
    fi
    echo "  playwright browser install failed. Recover (no sudo): npx playwright install chromium"
    echo "  If tests fail at browser LAUNCH with missing shared libraries (Linux only),"
    echo "  that needs OS packages via sudo, so it is never run automatically:"
    echo "      npx playwright install-deps chromium"
    echo "  (full log: $err)"
  }

  install_cypress_binary() {
    if ! have npx; then
      echo "  skip cypress binary: npx not found — $H_NODE"
      return
    fi
    echo "Installing Cypress binary…"
    local err="${CACHE_DIR}/cypress-err.log"
    if npx --yes cypress install >/dev/null 2>"$err"; then
      return
    fi
    echo "  cypress binary install failed. Recover (no sudo): npx cypress install"
    echo "  (full log: $err)"
  }

  if [ "$E2E_FRAMEWORK" = "playwright" ]; then
    install_playwright_browsers
  else
    install_cypress_binary
  fi

  echo "-- verify --"
  pw_state="missing"
  if [ "$E2E_FRAMEWORK" = "playwright" ]; then
    playwright_browsers_cached && pw_state="ok"
  else
    cypress_binary_cached && pw_state="ok"
  fi
  echo "  ${E2E_FRAMEWORK} browsers: $pw_state"
  echo "RESULT e2e_framework=$E2E_FRAMEWORK e2e_browsers=$pw_state"
  exit 0
fi

# --- MODE=install (codegraph + markitdown) ---
if [ "$ASSUME_YES" -ne 1 ]; then
  echo "This will run user-level npm/pip installs (no sudo). Re-run with --yes to proceed."
  exit 0
fi

# Ensure the cache dir exists BEFORE the installers use it (e.g. for the npm error
# log) — on a fresh HOME it does not exist yet.
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# codegraph via npm global. On a permission error (system-owned node prefix) retry
# with a user-owned prefix — never sudo, never interactive.
install_codegraph() {
  if ! have npm; then
    echo "  skip codegraph: npm not found — $H_NODE"
    return
  fi
  echo "Installing/updating codegraph..."
  local err="${CACHE_DIR}/npm-err.log"
  if npm i -g @colbymchenry/codegraph@latest >/dev/null 2>"$err"; then
    return
  fi
  if grep -qiE 'EACCES|permission denied|EPERM' "$err" 2>/dev/null; then
    local pfx="$HOME/.npm-global"
    echo "  npm global blocked by permissions — retrying in a user prefix ($pfx)…"
    if npm i -g --prefix "$pfx" @colbymchenry/codegraph@latest >/dev/null 2>&1; then
      echo "  installed to $pfx/bin — add it to PATH (a new shell picks it up):"
      echo "      export PATH=\"$pfx/bin:\$PATH\""
      return
    fi
  fi
  echo "  codegraph install failed. Recover (no sudo): npm i -g @colbymchenry/codegraph@latest"
  echo "  (full log: $err)"
}

# markitdown via pipx (isolated CLI + non-interactive PATH fix). Fallback to a user
# pip install that tolerates PEP 668 'externally-managed' environments.
install_markitdown() {
  if have pipx; then
    echo "Installing/updating markitdown (pipx)…"
    pipx install markitdown >/dev/null 2>&1 || pipx upgrade markitdown >/dev/null 2>&1 || true
    pipx ensurepath >/dev/null 2>&1 || true
    return
  fi
  if ! pick_python; then
    echo "  skip markitdown: no Python 3.8+ found — $H_PY"
    return
  fi
  # Prefer bootstrapping pipx (best cross-platform PATH handling), then use it.
  echo "Installing markitdown (via $PYTHON)…"
  if $PYTHON -m pipx --version >/dev/null 2>&1 \
     || $PYTHON -m pip install --user pipx >/dev/null 2>&1 \
     || $PYTHON -m pip install --user --break-system-packages pipx >/dev/null 2>&1; then
    $PYTHON -m pipx ensurepath >/dev/null 2>&1 || true
    if $PYTHON -m pipx install markitdown >/dev/null 2>&1 \
       || $PYTHON -m pipx upgrade markitdown >/dev/null 2>&1; then
      return
    fi
  fi
  # Last resort: user pip install (handles externally-managed with the escape hatch).
  if $PYTHON -m pip install --user -U markitdown >/dev/null 2>&1 \
     || $PYTHON -m pip install --user --break-system-packages -U markitdown >/dev/null 2>&1; then
    return
  fi
  echo "  markitdown install failed. Recover: $PYTHON -m pip install --user markitdown"
}

install_codegraph
install_markitdown

# --- Verify what actually landed, so the pipeline never re-offers a done install ---
echo "-- verify --"
hash -r 2>/dev/null || true
# ok = on PATH now; installed = present but needs a PATH refresh (new shell);
# missing = install did not land.
status() {
  if resolves "$1"; then echo "ok"
  elif installed_anywhere "$1"; then echo "installed"
  else echo "missing"; fi
}
cg="$(status codegraph)"
md="$(status markitdown)"
echo "  codegraph:  $cg"
echo "  markitdown: $md"
if [ "$cg" = installed ] || [ "$md" = installed ]; then
  echo "  note: 'installed' tools are ready in a NEW session (PATH refresh)."
fi

mkdir -p "$CACHE_DIR"
date +%s > "$CACHE_FILE"
# Machine-readable last line for Phase 0 to parse (ok|installed|missing per tool).
echo "RESULT codegraph=$cg markitdown=$md"
