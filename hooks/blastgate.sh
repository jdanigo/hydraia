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
# Nearest EXISTING ancestor (a Write may create new dirs) — never fall back to "." (the
# hook's cwd), which would misattribute an out-of-repo path to this repo.
dir="$(dirname "$file_path" 2>/dev/null || echo /)"
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do dir="$(dirname "$dir")"; done
[ -d "$dir" ] || exit 0
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

# Breaker state is the hooks' own ledger — the model never edits it (clearing a STALLED
# run or a spent budget is the human's call). routing is excluded: Phase 3 records the
# human's routing choice there.
case "$file_path" in
  "$adir"/.agents/ledger.json|"$adir"/.agents/verify.json|"$adir"/.agents/dispatched|"$adir"/.agents/finished|"$adir"/.agents/runid)
    echo "[hydraia] BLOCKED: Hydraia breaker state is written only by its hooks. Resetting it is the human's decision — tell the human instead." >&2
    exit 2 ;;
esac

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

# --- Plan-scope gate (per active-plan run) ----------------------------------
# A frozen plan declares, per task, the files it may touch (`**Files:**` lines). An edit
# outside that union is scope creep — the model widening the change without asking. Block
# it and send the decision back to the human (the executor reports NEEDS_DECISION; the
# human amends the plan and re-arms). Legacy plans with no **Files:** lines → no gate.
# Always allowed: lockfiles (regenerated by package managers). Markdown + artifacts are
# exempted above. scopeGate: strict (default) | warn | off.
aplan="$adir/.active-plan"
if [ -f "$aplan" ]; then
  apm="$(stat -c %Y "$aplan" 2>/dev/null || stat -f %m "$aplan" 2>/dev/null || echo 0)"
  if [ $(( $(date +%s) - apm )) -lt 43200 ]; then
    SCOPE="strict"; command -v hy_config >/dev/null 2>&1 && SCOPE="$(cd "$repo" && hy_config scopeGate strict HYDRAIA_SCOPE_GATE)"
    if [ "$SCOPE" != "off" ]; then
      ppath="$(head -1 "$aplan" 2>/dev/null | tr -d '\r' | sed 's/[[:space:]]*$//')"
      case "$ppath" in /*) : ;; ?*) ppath="$repo/$ppath" ;; esac
      if [ -n "$ppath" ] && [ -f "$ppath" ]; then
        verdict="$(HY_PLAN="$ppath" HY_REL="$rel" HY_REPO="$repo" python3 -c '
import os, re, fnmatch
rel = os.environ["HY_REL"]
LOCK = {"package-lock.json","pnpm-lock.yaml","yarn.lock","bun.lockb","bun.lock","go.sum",
        "Cargo.lock","poetry.lock","uv.lock","Gemfile.lock","composer.lock","Pipfile.lock"}
if os.path.basename(rel) in LOCK:
    print("ok"); raise SystemExit
declared, inreg, blank = [], False, False
field = re.compile(r"^\s*(?:[-*]\s*)?\*\*[^*]+:\*\*")
listish = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s|^\s{2,}\S")
span = re.compile(r"`(?:(?:Create|Modify|Test|Delete|Update|Edit|Add|Remove)\s*:\s*)?([^`\s]+)`", re.I)
fence = False
for line in open(os.environ["HY_PLAN"], errors="replace"):
    s = line.rstrip("\n")
    if s.lstrip().startswith("```"):
        fence = not fence
        continue
    if fence:
        continue
    if re.match(r"^\s*(?:[-*]\s*)?\*\*Files:\*\*", s):
        inreg, blank = True, False
    elif inreg:
        if not s.strip():
            blank = True          # blank lines inside the region are fine (list after a blank)
            continue
        if s.startswith("#") or field.match(s) or (blank and not listish.match(s)):
            inreg = False         # next heading / next **Field:** / prose after a blank line
        blank = False
    if inreg:
        for tok in span.findall(s):
            tok = re.sub(r":\d+(?:-\d+)?$", "", tok)   # drop a trailing :line / :a-b
            if tok.startswith("./"):
                tok = tok[2:]
            if "/" in tok or "." in tok:
                declared.append(tok)
if not declared:
    print("nogate"); raise SystemExit
def expand(p):  # {a,b} brace lists → alternatives
    m = re.search(r"\{([^{}]*)\}", p)
    if not m: return [p]
    return [x for alt in m.group(1).split(",") for x in expand(p[:m.start()] + alt + p[m.end():])]
for d in declared:
    for p in expand(d):
        isdir = p.endswith("/") or os.path.isdir(os.path.join(os.environ["HY_REPO"], p))
        pre = p if p.endswith("/") else p + "/"
        if rel == p or (isdir and rel.startswith(pre)) or fnmatch.fnmatch(rel, p):
            print("ok"); raise SystemExit
print("out")
' 2>/dev/null || echo ok)"
        if [ "$verdict" = "out" ]; then
          if [ "$SCOPE" = "warn" ]; then
            echo "[hydraia] note: \"$rel\" is outside the frozen plan's declared Files (scope creep?)." >&2
          else
            cat >&2 <<EOF
[hydraia] BLOCKED: plan-scope gate.

"$rel" is not in any task's **Files:** in the frozen plan:
  $ppath
Touching it widens the change beyond what the human approved. Do NOT work around this.
Stop and report NEEDS_DECISION: which file, why the plan needs it, and the smallest
alternative inside the declared files. The HUMAN decides — amend the plan's Files and
re-arm, or bypass once: export HYDRAIA_ALLOW_DIRECT=1  (scopeGate=warn|off in config).
EOF
            exit 2
          fi
        fi
      fi
    fi
  fi
fi

# --- maxFiles advisory (per active-plan run) --------------------------------
# Count distinct files edited this run. Warn past maxFiles; block only if enforced.
plan="$adir/.active-plan"
[ -f "$plan" ] || exit 0                 # only meaningful during an active run
acount_dir="$adir/.agents"; mkdir -p "$acount_dir" 2>/dev/null || exit 0
efile="$acount_dir/edited-files"
# Reset the maxFiles set per run, like the other counters. The run id is the .active-plan
# mtime; when it changes (a new run armed the plan) the previous run's file set is stale,
# so truncate it and record the new run id before counting. Fail-open on any error.
rid_file="$acount_dir/edited-files.runid"
cur_runid="$(stat -c %Y "$plan" 2>/dev/null || stat -f %m "$plan" 2>/dev/null || echo 0)"
prev_runid="$(cat "$rid_file" 2>/dev/null || echo)"
if [ "$cur_runid" != "$prev_runid" ]; then
  : > "$efile" 2>/dev/null || true
  printf '%s' "$cur_runid" > "$rid_file" 2>/dev/null || true
fi
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
