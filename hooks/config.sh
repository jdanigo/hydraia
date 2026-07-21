#!/usr/bin/env bash
# Hydraia config resolver — sourced by the other hooks.
#
# Precedence (highest first): environment override > per-repo config
# (docs/hydraia/config.json) > global config (~/.config/hydraia/config.json) >
# built-in default. The dashboard writes the JSON files; env vars stay the
# un-forgeable last word (e.g. HYDRAIA_ALLOW_DIRECT is never file-configurable).
#
#   value="$(hy_config maxTotalAgents 30 HYDRAIA_MAX_AGENTS)"
#
# Fails open to the default on any error — config must never wedge a hook.

hy_config() {
  local key="$1" def="$2" envvar="${3:-}"
  if [ -n "$envvar" ]; then
    local ev="${!envvar:-}"
    [ -n "$ev" ] && { printf '%s' "$ev"; return 0; }
  fi
  command -v python3 >/dev/null 2>&1 || { printf '%s' "$def"; return 0; }
  local repo_root repo_cfg global_cfg adir
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  adir="$(hy_artifacts_dir)"
  repo_cfg="${adir:+$adir/config.json}"
  global_cfg="${HOME}/.config/hydraia/config.json"
  python3 - "$key" "$def" "$repo_cfg" "$global_cfg" <<'PY' 2>/dev/null || printf '%s' "$def"
import json, sys
key, default = sys.argv[1], sys.argv[2]
for p in sys.argv[3:]:
    if not p:
        continue
    try:
        with open(p) as f:
            d = json.load(f)
        if isinstance(d, dict) and d.get(key) is not None:
            v = d[key]
            sys.stdout.write("true" if v is True else "false" if v is False else str(v))
            sys.exit(0)
    except Exception:
        pass
sys.stdout.write(default)
PY
}

# Read repos[<git root>].<key> from the GLOBAL config only (never the per-repo
# file — this is what tells us WHERE the per-repo file lives). Prints default on
# any miss/error. Used to resolve the artifacts dir without a chicken/egg.
#
#   dir="$(hy_repo_config artifactsDir "")"
hy_repo_config() {
  local key="$1" def="${2:-}"
  command -v python3 >/dev/null 2>&1 || { printf '%s' "$def"; return 0; }
  local repo_root global_cfg
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$repo_root" ] || { printf '%s' "$def"; return 0; }
  global_cfg="${HOME}/.config/hydraia/config.json"
  python3 - "$key" "$def" "$repo_root" "$global_cfg" <<'PY' 2>/dev/null || printf '%s' "$def"
import json, sys
key, default, root, path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(path) as f:
        d = json.load(f)
    repos = d.get("repos") if isinstance(d, dict) else None
    entry = repos.get(root) if isinstance(repos, dict) else None
    if isinstance(entry, dict) and entry.get(key) is not None:
        v = entry[key]
        sys.stdout.write("true" if v is True else "false" if v is False else str(v))
        sys.exit(0)
except Exception:
    pass
sys.stdout.write(default)
PY
}

# Resolve the absolute base dir where Hydraia writes ALL artifacts + control-plane
# for the current repo. Precedence: env HYDRAIA_DOCS_DIR > global
# repos[<root>].artifactsDir > <repo root>/docs/hydraia. Never creates anything;
# fails open to the in-repo default. No git root -> "docs/hydraia".
hy_artifacts_dir() {
  local env_dir="${HYDRAIA_DOCS_DIR:-}"
  [ -n "$env_dir" ] && { printf '%s' "$env_dir"; return 0; }
  local cfg_dir repo_root
  cfg_dir="$(hy_repo_config artifactsDir "")"
  [ -n "$cfg_dir" ] && { printf '%s' "$cfg_dir"; return 0; }
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root" ]; then
    printf '%s' "$repo_root/docs/hydraia"
  else
    printf '%s' "docs/hydraia"
  fi
}

# Deterministically set repos[<root>].<key> in the GLOBAL config
# (~/.config/hydraia/config.json), preserving every other repo and key. This is the
# sanctioned way for the main thread to record the storage-gate choice — never
# hand-edit the JSON, which risks clobbering other repos or writing malformed config.
# Creates the file and its parent dir if missing; writes atomically (tmp + rename).
# Value coercion: "true"/"false" → JSON bool, all-digits → JSON number, else string.
# Returns non-zero (and leaves the file untouched) on any error.
#
#   hy_config_set "$repo_root" artifactsDir "/abs/external/base"   # external mode
#   hy_config_set "$repo_root" artifactsDir docs/hydraia            # in-repo (or omit)
#   hy_config_set "$repo_root" autoCommit false
hy_config_set() {
  local root="$1" key="$2" value="${3-}"
  [ -n "$root" ] && [ -n "$key" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  local cfg="${HOME}/.config/hydraia/config.json"
  mkdir -p "$(dirname "$cfg")" 2>/dev/null || return 1
  HY_CFG="$cfg" HY_ROOT="$root" HY_KEY="$key" HY_VAL="$value" python3 - <<'PY'
import json, os
cfg  = os.environ["HY_CFG"]
root = os.environ["HY_ROOT"]
key  = os.environ["HY_KEY"]
raw  = os.environ["HY_VAL"]
if raw == "true":
    val = True
elif raw == "false":
    val = False
elif raw.lstrip("-").isdigit():
    val = int(raw)
else:
    val = raw
try:
    with open(cfg) as f:
        d = json.load(f)
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}
repos = d.get("repos")
if not isinstance(repos, dict):
    repos = {}
    d["repos"] = repos
entry = repos.get(root)
if not isinstance(entry, dict):
    entry = {}
    repos[root] = entry
entry[key] = val
tmp = cfg + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.replace(tmp, cfg)
PY
}
