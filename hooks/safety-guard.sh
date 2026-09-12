#!/usr/bin/env bash
# Hydraia safety-guard (PreToolUse on Bash). ECC-inspired.
#
# Blocks destructive shell commands during autonomous runs, and (when the orchestrator
# sets HYDRAIA_WRITE_SCOPE) confines writes to one subtree. Distinct from blastgate.sh
# (which gates Edit/Write paths); this gates Bash command STRINGS.
#
# Blocks (exit 2) only when: repo opts in, human bypass unset, safetyGuard != off, and the
# command matches a destructive pattern (or writes outside the write-scope). Fail-open.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true

payload="$(cat 2>/dev/null || true)"
command -v python3 >/dev/null 2>&1 || exit 0
[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0

cmd="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin); ti = d.get("tool_input") or {}
    print(ti.get("command") or "")
except Exception:
    print("")
' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0
adir="$(cd "$repo" 2>/dev/null && hy_artifacts_dir 2>/dev/null)"; [ -n "$adir" ] || adir="$repo/docs/hydraia"
if [ ! -d "$adir" ] \
   && [ -z "$(cd "$repo" 2>/dev/null && hy_repo_config artifactsDir "" 2>/dev/null)" ] \
   && [ ! -d "$repo/docs/hydraia" ]; then
  exit 0
fi

MODE="on"; command -v hy_config >/dev/null 2>&1 && MODE="$(hy_config safetyGuard on HYDRAIA_SAFETY_GUARD)"
[ "$MODE" = "off" ] && exit 0

block=""
case "$cmd" in
  *"rm -rf /"*|*"rm -fr /"*)                          block="rm -rf on an absolute root path" ;;
  *"rm -rf ~"*|*'rm -rf $HOME'*)                      block="rm -rf on home" ;;
  *"git push"*"--force"*|*"git push"*" -f"*|*"push --force"*) block="git force-push" ;;
  *"git reset --hard"*)                               block="git reset --hard (discards work)" ;;
  *"DROP TABLE"*|*"DROP DATABASE"*|*"TRUNCATE "*)     block="destructive SQL (DROP/TRUNCATE)" ;;
  *"--no-verify"*)                                    block="--no-verify (skips commit hooks)" ;;
  *"chmod -R 777"*)                                   block="chmod -R 777 (insecure perms)" ;;
  *"mkfs"*)                                           block="filesystem format" ;;
  *"curl "*"| sh"*|*"curl "*"| bash"*|*"wget "*"| sh"*|*"wget "*"| bash"*) block="curl|wget pipe-to-shell" ;;
esac

if [ -n "$block" ]; then
  {
    echo "[hydraia] BLOCKED: safety-guard — $block."
    echo "Command: $cmd"
    echo "Destructive ops are not run autonomously. The HUMAN runs it, or set HYDRAIA_ALLOW_DIRECT=1."
    echo "Disable with safetyGuard=off."
  } >&2
  exit 2
fi

scope="${HYDRAIA_WRITE_SCOPE:-}"
if [ -n "$scope" ]; then
  case "$cmd" in
    *" > "*|*" >> "*|*"tee "*|*"sed -i"*|*"mv "*|*"cp "*)
      outside="$(HY_CMD="$cmd" HY_SCOPE="$scope" HY_REPO="$repo" python3 -c '
import os, re
cmd=os.environ["HY_CMD"]; scope=os.environ["HY_SCOPE"]; repo=os.environ["HY_REPO"]
toks=re.findall(r"[\w./\-]+", cmd); bad=""
for t in toks:
    if t.startswith(("/tmp","/var/tmp","/dev/null")): continue
    if "/" in t and not t.startswith(("http","-",".git")):
        ap=os.path.abspath(os.path.join(repo,t)) if not t.startswith("/") else t
        if ap.startswith(repo) and not ap.startswith(os.path.abspath(scope)) and "." in os.path.basename(ap):
            bad=t; break
print(bad)
' 2>/dev/null || true)"
      if [ -n "$outside" ]; then
        echo "[hydraia] BLOCKED: safety-guard write-scope — '$outside' is outside the story scope ($scope). Override with HYDRAIA_ALLOW_DIRECT=1." >&2
        exit 2
      fi
      ;;
  esac
fi
exit 0
