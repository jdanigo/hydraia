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
  local repo_root repo_cfg global_cfg
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  repo_cfg="${repo_root:+$repo_root/docs/hydraia/config.json}"
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
