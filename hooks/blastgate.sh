#!/usr/bin/env bash
# Hydraia blast-radius gate (PreToolUse on Edit|Write|MultiEdit).
#
# Blocks edits to sensitive paths (secrets, auth, payments, migrations, …) defined in
# gate.yaml's denylist, and warns past a per-run file-count ceiling. This is the safety
# gate the spec-drive gate.sh does NOT provide. Distinct concern, separate file.
#
# Blocks (exit 2) only when ALL hold: target repo opts in, human bypass unset, pathGate
# not off, target is not a pipeline artifact/markdown, and the path matches a denylist glob.
# On any internal error it ALLOWS (fail-open).
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/config.sh" 2>/dev/null || true

payload="$(cat 2>/dev/null || true)"
command -v python3 >/dev/null 2>&1 || exit 0

file_path="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin); ti = d.get("tool_input") or {}
    print(ti.get("file_path") or ti.get("path") or "")
except Exception:
    print("")
' 2>/dev/null || true)"
[ -n "$file_path" ] || exit 0

# Human bypass.
[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0

# Resolve repo + opt-in (identical test to gate.sh).
dir="$(dirname "$file_path" 2>/dev/null || echo .)"; [ -d "$dir" ] || dir="."
repo="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0
adir="$(cd "$repo" 2>/dev/null && hy_artifacts_dir)"; [ -n "$adir" ] || adir="$repo/docs/hydraia"
if [ ! -d "$adir" ] \
   && [ -z "$(cd "$repo" 2>/dev/null && hy_repo_config artifactsDir "")" ] \
   && [ ! -d "$repo/docs/hydraia" ]; then
  exit 0
fi

# Mode.
PATH_GATE="strict"
command -v hy_config >/dev/null 2>&1 && PATH_GATE="$(hy_config pathGate strict HYDRAIA_PATH_GATE)"
[ "$PATH_GATE" = "off" ] && exit 0

# Exempt pipeline artifacts + markdown (same as gate.sh).
case "$file_path" in *.md|*.markdown) exit 0 ;; esac
case "$file_path" in "$adir"/*|"$repo"/docs/hydraia/*|docs/hydraia/*) exit 0 ;; esac

# Repo-relative path for glob matching.
rel="${file_path#"$repo"/}"

# Load denylist from gate.yaml (repo), else built-in default. Match with python fnmatch
# (glob '**' handled by also testing each path suffix). Prints "HIT <rule>" or nothing.
gy="$repo/gate.yaml"
hit="$(HY_REL="$rel" HY_GY="$gy" python3 -c '
import os, fnmatch
rel = os.environ["HY_REL"]; gy = os.environ["HY_GY"]
default = [".env",".env.*","**/secrets/**","**/credentials/**","**/*_key*","**/*_secret*",
           ".terraform/**","k8s/production/**","**/migrations/**","auth/**","payments/**","billing/**"]
rules = []
try:
    inlist = False
    for line in open(gy):
        s = line.strip()
        if s.startswith("denylist:"): inlist = True; continue
        if inlist:
            if s.startswith("- "):
                rules.append(s[2:].strip().strip("\"'"'"'"))
            elif s and not s.startswith("#") and not s.startswith("- "):
                break
except Exception:
    rules = []
if not rules: rules = default
def match(rule, path):
    if fnmatch.fnmatch(path, rule): return True
    # emulate "**/" prefix and "/**" suffix against path segments
    r = rule.replace("**/", "").replace("/**", "")
    if fnmatch.fnmatch(path, r) or fnmatch.fnmatch(path, "*/"+r) or fnmatch.fnmatch(path, r+"/*"): return True
    if ("/"+rule.replace("**","").strip("/")+"/") in ("/"+path+"/"): return True
    return False
for r in rules:
    if match(r, rel): print("HIT "+r); break
' 2>/dev/null || true)"

if [ -n "$hit" ]; then
  rule="${hit#HIT }"
  cat >&2 <<EOF
[hydraia] BLOCKED: blast-radius gate.

The path "$rel" matches a denylisted rule in gate.yaml: "$rule".
Hydraia refuses edits to secrets, auth, payments, infra, and migration paths — even
under model instruction — because a wrong edit here is high-blast-radius.

If this edit is genuinely intended, the HUMAN authorizes it (never the model):
  export HYDRAIA_ALLOW_DIRECT=1
or remove/adjust the rule in gate.yaml. To disable the gate entirely: set pathGate=off.
EOF
  exit 2
fi

# --- maxFiles advisory (per active-plan run) --------------------------------
# Count distinct files edited this run. Warn past maxFiles; block only if enforced.
plan="$adir/.active-plan"
[ -f "$plan" ] || exit 0                 # only meaningful during an active run
acount_dir="$adir/.agents"; mkdir -p "$acount_dir" 2>/dev/null || exit 0
efile="$acount_dir/edited-files"
grep -qxF "$rel" "$efile" 2>/dev/null || printf '%s\n' "$rel" >> "$efile" 2>/dev/null || true
MAXF="10"; command -v hy_config >/dev/null 2>&1 && MAXF="$(hy_config maxFiles 10)"
case "$MAXF" in ''|*[!0-9]*) MAXF=10 ;; esac
# gate.yaml maxFiles overrides config default if present.
gyf="$(grep -E '^maxFiles:' "$gy" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
[ -n "$gyf" ] && MAXF="$gyf"
n="$(sort -u "$efile" 2>/dev/null | wc -l | tr -d ' ')"; n="${n:-0}"
if [ "$n" -gt "$MAXF" ]; then
  ENF="false"; command -v hy_config >/dev/null 2>&1 && ENF="$(hy_config maxFilesEnforce false HYDRAIA_MAX_FILES_ENFORCE)"
  if [ "$ENF" = "true" ]; then
    echo "[hydraia] BLOCKED: blast-radius — this run has touched $n distinct files (max $MAXF). Consolidate or raise maxFiles." >&2
    exit 2
  fi
  echo "[hydraia] note: this run has touched $n distinct files (advisory max $MAXF). Large diff — confirm scope." >&2
fi
exit 0
