# Loop-Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five loop-engineering mechanisms to hydraia — circuit breaker, cost/caps, blast-radius path gate, binding constraints, autonomy tiers — as runtime guarantees, without regressing Claude behavior or touching the parallel Codex port.

**Architecture:** New dedicated bash hook (`blastgate.sh`) + extensions to the existing `agents.sh` / `preflight.sh` / `summary.sh` hooks, all reading shared agent-agnostic data files (`gate.yaml`, `constraints.md`, `ledger.json`, `cost.yaml`). SKILL prose changes drive the tiers/early-exit/escalation. Every hook fails open, is opt-in per repo, and honors an env-var human bypass. Spec: `docs/hydraia/specs/2026-08-19-loop-hardening-design.md`.

**Tech Stack:** Bash + python3 (already a hydraia prerequisite; all JSON/YAML/glob parsing goes through python3 for portability, exactly like the existing hooks). No new runtime deps.

## Global Constraints

- **Fail open:** any internal hook error → allow (exit 0). A hook must never wedge editing or a run. Copied verbatim from every existing hook.
- **Opt-in per repo:** enforce only where hydraia is in use — resolved artifacts base exists, OR repo registered in `~/.config/hydraia/config.json`, OR legacy `docs/hydraia/` exists. Reuse the exact test from `hooks/gate.sh`.
- **Human bypass is env-only:** `HYDRAIA_ALLOW_DIRECT=1` lifts breaker + path gate; `HYDRAIA_PAUSE=1` is the kill switch. Never model-forgeable, never file-configurable for the bypass itself.
- **Config via `hy_config`:** read every tunable with `hy_config <key> <default> <ENVVAR>` (sourced from `hooks/config.sh`). Defaults live in the plan; dashboard writes the JSON.
- **No attribution trailer** on any commit (hydraia rule — never add `Co-Authored-By: Claude`).
- **Do NOT edit `codex/`** — owned by the parallel Codex session. The parity checklist artifact is the only interface.
- **Block contract:** a blocking hook exits `2`, writes the human-readable reason to **stderr**, and (for Task hooks) may also emit a JSON decision; an allowing hook exits `0`. Matches `agents.sh` / `gate.sh`.
- **Artifacts base `$hbase`** is resolved with `hy_artifacts_dir` run from the repo root; fall back to `$repo/docs/hydraia`.

---

## Task 1: Shared data files (gate.yaml, cost.yaml, constraints sample, budget doc)

Pure data + docs, no logic. These are the agent-agnostic files both Claude and Codex read.

**Files:**
- Create: `gate.yaml`
- Create: `gate.yaml.sample`
- Create: `patterns/cost.yaml`
- Create: `docs/hydraia/constraints.sample.md`
- Create: `loop-budget.md`
- Test: `hooks/tests/fixtures/` (referenced later) + a parse check below

**Interfaces:**
- Produces: `gate.yaml` (keys `version`, `denylist[]`, `maxFiles`, `autoMergeAllowlist[]`), consumed by Task 3 (`blastgate.sh`) and Task 9 (tier risk detection); `patterns/cost.yaml` (keys `version`, `routes{}`, `defaults{}`) consumed by Task 9; `docs/hydraia/constraints.sample.md` copied by users to `constraints.md`, consumed by Task 7 + Task 10.

- [ ] **Step 1: Create `gate.yaml`**

```yaml
# Hydraia blast-radius gate. Machine-readable path denylist + file-count guard,
# enforced by hooks/blastgate.sh. Denylisted paths are BLOCKED for Edit/Write/MultiEdit
# unless the human sets HYDRAIA_ALLOW_DIRECT=1. Ported from loop-engineering gate.yaml.
version: 1

denylist:
  - ".env"
  - ".env.*"
  - "**/secrets/**"
  - "**/credentials/**"
  - "**/*_key*"
  - "**/*_secret*"
  - ".terraform/**"
  - "k8s/production/**"
  - "**/migrations/**"
  - "auth/**"
  - "payments/**"
  - "billing/**"

# Max distinct files an active-plan run may touch before blastgate warns (advisory by
# default; set maxFilesEnforce=true in config to make it a hard block).
maxFiles: 10

# Data only — reserved for the future loop patterns (item #6). Nothing consumes it yet.
autoMergeAllowlist:
  - "docs/**"
  - "**/*.md"
```

- [ ] **Step 2: Copy it to the sample**

Run: `cp gate.yaml gate.yaml.sample`
Expected: identical file at `gate.yaml.sample` (shipped default; `gate.yaml` is the live one a repo may edit).

- [ ] **Step 3: Create `patterns/cost.yaml`**

```yaml
# Hydraia pre-flight cost model. Rough order-of-magnitude token anchors per route × tier,
# printed by the orchestrator at Phase -1. Editable data — not a promise. Ported/adapted
# from loop-engineering patterns/registry.yaml cost blocks.
version: 1

routes:
  feature:
    S: { tokens_noop: 5000, tokens_report: 40000, tokens_action: 200000 }
    M: { tokens_noop: 5000, tokens_report: 60000, tokens_action: 600000 }
    L: { tokens_noop: 5000, tokens_report: 80000, tokens_action: 1500000 }
  review:
    any: { tokens_noop: 5000, tokens_action: 120000 }
  perf:
    any: { tokens_noop: 5000, tokens_action: 300000 }
  db:
    any: { tokens_noop: 5000, tokens_action: 300000 }
  story:
    any: { tokens_noop: 5000, tokens_action: 150000 }
  architect:
    any: { tokens_noop: 5000, tokens_action: 400000 }

defaults:
  suggested_daily_cap: 0     # 0 = off (opt-in); mirrors dailyTokenCap default
```

- [ ] **Step 4: Create `docs/hydraia/constraints.sample.md`**

```markdown
# Hydraia Constraints — <repo>

> Copy this file to `constraints.md` (same dir) to activate. It is read at the start of
> every session (injected as binding context by hooks/preflight.sh) and again in Phase 0.
> Rules here are BINDING — the agent must follow them. Keep it short (< 8 KB).

## Push & Merge
- Don't push before telling me.
- Never merge to main without human approval.

## Paths
- Never edit `.env`, `auth/`, `payments/`, `secrets/`, `credentials/` (also enforced by gate.yaml).
- Name any module the agent must not touch here.

## Code
- Run the project's tests before proposing a fix.
- Never disable a test to make CI green.
- One focused change per run — no unrelated refactors.

## Communication
- Say what you're about to do before doing it.
- Never close an issue or PR without approval.

## Budget
- If token spend hits the daily cap, switch to report-only.
- If HYDRAIA_PAUSE is set, exit immediately.
```

- [ ] **Step 5: Create `loop-budget.md`**

```markdown
# Loop Budget — Hydraia

Human-readable companion to the token-cap config keys (enforced by hooks/agents.sh).

## Caps (config keys, default 0 = off)
| Key | Meaning |
|-----|---------|
| `dailyTokenCap` | Max in+out tokens (all runs) per rolling 24h before new sub-agent dispatch is blocked. |
| `perRunTokenCap` | Same, scoped to the current run. |
| `loopPause` / `HYDRAIA_PAUSE` | Kill switch — blocks all sub-agent dispatch immediately. |

## On cap exceed
1. Hooks block new Task dispatch; the orchestrator switches to report-only and surfaces the blocker.
2. Raise the cap (`export HYDRAIA_DAILY_TOKEN_CAP=…`) or clear the pause to resume — the human's call.

## Estimate
Phase -1 prints a per-route estimate from `patterns/cost.yaml`. Edit that file to retune anchors.
```

- [ ] **Step 6: Verify all data files parse**

Run:
```bash
python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in ['gate.yaml','gate.yaml.sample','patterns/cost.yaml']]; print('yaml ok')" 2>/dev/null \
  || python3 -c "import json; print('yaml lib absent — skip')"
test -f docs/hydraia/constraints.sample.md && test -f loop-budget.md && echo "docs ok"
```
Expected: `yaml ok` (or the skip note if pyyaml absent) and `docs ok`.

> Note: the hooks parse `gate.yaml` with a tiny hand-rolled python reader (Task 3), NOT pyyaml — pyyaml is not a hydraia dependency. This step's yaml check is best-effort validation only.

- [ ] **Step 7: Commit**

```bash
git add gate.yaml gate.yaml.sample patterns/cost.yaml docs/hydraia/constraints.sample.md loop-budget.md
git commit -m "feat(loop-hardening): shared data files — gate.yaml, cost.yaml, constraints sample, budget doc"
```

---

## Task 2: Hook test harness

A minimal shell harness so every hook task can assert exit codes against JSON fixtures.

**Files:**
- Create: `hooks/tests/run.sh`
- Create: `hooks/tests/lib.sh`

**Interfaces:**
- Produces: `assert_exit <expected> <hook> <payload-json> [env...]` and `assert_stderr <substr> <hook> <payload>` helpers used by Tasks 3, 5, 6, 7. A test file is `hooks/tests/test-<hook>.sh`; `run.sh` sources `lib.sh` and runs every `test-*.sh`.

- [ ] **Step 1: Write `hooks/tests/lib.sh`**

```bash
#!/usr/bin/env bash
# Minimal assert helpers for hydraia hook tests. A hook reads its JSON payload on stdin
# and signals via exit code (0 allow, 2 block). These run the hook with a payload + env
# and assert the result. No framework — portable bash.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

# assert_exit <expected-code> <hook-name> <payload-json> [ENV=val ...]
assert_exit() {
  local want="$1" hook="$2" payload="$3"; shift 3
  local out code
  out="$(printf '%s' "$payload" | env "$@" "$HOOKS_DIR/$hook" 2>/dev/null)"; code=$?
  if [ "$code" = "$want" ]; then PASS=$((PASS+1)); printf '  ok   %s exit=%s\n' "$hook" "$code"
  else FAIL=$((FAIL+1)); printf '  FAIL %s want=%s got=%s\n' "$hook" "$want" "$code"; fi
}

# assert_stderr <substring> <hook-name> <payload-json> [ENV=val ...]
assert_stderr() {
  local want="$1" hook="$2" payload="$3"; shift 3
  local err
  err="$(printf '%s' "$payload" | env "$@" "$HOOKS_DIR/$hook" 2>&1 >/dev/null)"
  if printf '%s' "$err" | grep -qF "$want"; then PASS=$((PASS+1)); printf '  ok   %s stderr~%s\n' "$hook" "$want"
  else FAIL=$((FAIL+1)); printf '  FAIL %s missing stderr %s\n' "$hook" "$want"; fi
}

report() { printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"; [ "$FAIL" = 0 ]; }
```

- [ ] **Step 2: Write `hooks/tests/run.sh`**

```bash
#!/usr/bin/env bash
# Run every hydraia hook test. Usage: bash hooks/tests/run.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/lib.sh"
for t in "$DIR"/test-*.sh; do
  [ -f "$t" ] || continue
  printf '── %s\n' "$(basename "$t")"
  # shellcheck source=/dev/null
  . "$t"
done
report
```

- [ ] **Step 3: Make executable + run the empty harness**

Run: `chmod +x hooks/tests/run.sh hooks/tests/lib.sh && bash hooks/tests/run.sh`
Expected: `0 passed, 0 failed` (no `test-*.sh` yet), exit 0.

- [ ] **Step 4: Commit**

```bash
git add hooks/tests/run.sh hooks/tests/lib.sh
git commit -m "test(hooks): minimal hook test harness (assert_exit/assert_stderr)"
```

---

## Task 3: blastgate.sh — path denylist + file-count guard (Feature 3)

**Files:**
- Create: `hooks/blastgate.sh`
- Test: `hooks/tests/test-blastgate.sh`

**Interfaces:**
- Consumes: `hooks/config.sh` (`hy_config`, `hy_artifacts_dir`, `hy_repo_config`), `gate.yaml` (denylist/maxFiles).
- Produces: a `PreToolUse:Edit|Write|MultiEdit` hook. Exit 2 + stderr on denylist hit; exit 0 otherwise.

- [ ] **Step 1: Write the failing tests**

```bash
# hooks/tests/test-blastgate.sh
REPO="$(git rev-parse --show-toplevel)"
mkdir -p "$REPO/docs/hydraia"   # opt-in: make this repo a hydraia repo for the test
DENY="{\"tool_input\":{\"file_path\":\"$REPO/auth/login.ts\"}}"
OK="{\"tool_input\":{\"file_path\":\"$REPO/src/util.ts\"}}"
MD="{\"tool_input\":{\"file_path\":\"$REPO/README.md\"}}"
assert_exit 2 blastgate.sh "$DENY"
assert_exit 0 blastgate.sh "$OK"
assert_exit 0 blastgate.sh "$MD"
assert_exit 0 blastgate.sh "$DENY" HYDRAIA_ALLOW_DIRECT=1
assert_exit 0 blastgate.sh "$DENY" HYDRAIA_PATH_GATE=off
assert_stderr "blast-radius" blastgate.sh "$DENY"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash hooks/tests/run.sh`
Expected: FAIL — `hooks/blastgate.sh` does not exist yet (non-zero exits / missing file).

- [ ] **Step 3: Write `hooks/blastgate.sh`**

```bash
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
```

- [ ] **Step 4: Make executable, run tests**

Run: `chmod +x hooks/blastgate.sh && bash hooks/tests/run.sh`
Expected: all blastgate assertions PASS (deny→2, ok→0, md→0, bypass→0, off→0, stderr contains "blast-radius").

- [ ] **Step 5: Clean the test's opt-in dir if it was created only for the test**

Run: `git status --porcelain docs/hydraia | head` — if the test created `docs/hydraia/` in a non-hydraia checkout, leave it (this repo already uses `docs/hydraia/`). No action needed here since hydraia's own repo has it.

- [ ] **Step 6: Commit**

```bash
git add hooks/blastgate.sh hooks/tests/test-blastgate.sh
git commit -m "feat(loop-hardening): blastgate.sh — path denylist + file-count guard (gate.yaml)"
```

---

## Task 4: Wire blastgate into hooks.json

**Files:**
- Modify: `hooks/hooks.json` (PreToolUse `Edit|Write|MultiEdit` block)

**Interfaces:**
- Consumes: `hooks/blastgate.sh` from Task 3.

- [ ] **Step 1: Add blastgate to the Edit|Write|MultiEdit matcher**

In `hooks/hooks.json`, the `PreToolUse` array's first entry matches `Edit|Write|MultiEdit` and runs `gate.sh`. Add `blastgate.sh` as a second command in the SAME matcher's `hooks` array (both run; either can block):

```json
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/gate.sh\"",
            "async": false
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/blastgate.sh\"",
            "async": false
          }
        ]
      },
```

- [ ] **Step 2: Validate JSON**

Run: `python3 -c "import json; json.load(open('hooks/hooks.json')); print('json ok')"`
Expected: `json ok`.

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat(loop-hardening): wire blastgate.sh into PreToolUse Edit|Write|MultiEdit"
```

---

## Task 5: Circuit breaker in agents.sh (Feature 1)

Extend the existing agent-budget hook: count per-task-slug executor attempts and per-run reviewer cycles in a ledger; block past the caps.

**Files:**
- Modify: `hooks/agents.sh` (inside the Task critical section, after `reset_if_new_run`, before the total/concurrent decision)
- Test: `hooks/tests/test-breaker.sh`

**Interfaces:**
- Consumes: existing `agents.sh` lock + `$adir` (`$hbase/.agents`) + `pm` (runId) + `reset_if_new_run`.
- Produces: `$adir/ledger.json` (schema in spec). Blocks exit 2 with escalation stderr.

- [ ] **Step 1: Write the failing tests**

```bash
# hooks/tests/test-breaker.sh
REPO="$(git rev-parse --show-toplevel)"
AD="$REPO/docs/hydraia/.agents"; mkdir -p "$AD"
touch "$REPO/docs/hydraia/.active-plan"
: > "$AD/ledger.json"
P='{"hook_event_name":"PreToolUse","tool_name":"Task","cwd":"'"$REPO"'","tool_input":{"subagent_type":"hydraia-executor","description":"[task:widget] build widget"}}'
# First two dispatches allowed (attempts 1,2 <= maxTaskRetries=2), third blocked.
assert_exit 0 agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
assert_exit 0 agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
assert_exit 2 agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
assert_stderr "breaker" agents.sh "$P" HYDRAIA_MAX_TASK_RETRIES=2
# Bypass lifts it.
assert_exit 0 agents.sh "$P" HYDRAIA_ALLOW_DIRECT=1
```

> Note: the test must reset state between the three counted dispatches by keeping the same active-plan mtime (same runId) — do NOT re-touch `.active-plan` between them. Add `rm -f "$AD/ledger.json" "$AD/dispatched" "$AD/finished" "$AD/runid"` at the TOP of the test so each `run.sh` invocation starts clean.

- [ ] **Step 2: Run to verify it fails**

Run: `bash hooks/tests/run.sh`
Expected: FAIL — the third dispatch currently returns 0 (no breaker yet).

- [ ] **Step 3: Add the breaker block to `agents.sh`**

In `hooks/agents.sh`, immediately AFTER the `reset_if_new_run` call that precedes the `disp=`/`fin=` counting (around line 155), and AFTER the `HYDRAIA_ALLOW_DIRECT` early-allow already present at line 119, insert:

```bash
# --- Circuit breaker: per-item attempt ledger --------------------------------
# Count executor attempts per task-slug and reviewer cycles per run. Block past the
# caps and tell the orchestrator to escalate, mechanizing the Phase 4/5 soft caps.
MAX_RETRIES="$(hy_config maxTaskRetries 2 HYDRAIA_MAX_TASK_RETRIES 2>/dev/null || echo 2)"
MAX_REVIEW="$(hy_config maxReviewCycles 2 HYDRAIA_MAX_REVIEW_CYCLES 2>/dev/null || echo 2)"
case "$MAX_RETRIES" in ''|*[!0-9]*) MAX_RETRIES=2 ;; esac
case "$MAX_REVIEW" in ''|*[!0-9]*) MAX_REVIEW=2 ;; esac
ledger="$adir/ledger.json"

# Extract subagent_type + description from the payload for slug/role resolution.
brk="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin); ti = d.get("tool_input") or {}
    print((ti.get("subagent_type") or "") + "\t" + (ti.get("description") or ""))
except Exception:
    print("\t")
' 2>/dev/null || true)"
sub_type="$(printf '%s' "$brk" | awk -F'\t' '{print $1}')"
sub_desc="$(printf '%s' "$brk" | awk -F'\t' '{print $2}')"

# Role: reviewer agent types use a per-run review-cycle key; everything else is an
# executor keyed by its [task:<slug>] tag (fallback: hash of the description).
case "$sub_type" in
  *review*|*reviewer*|silent-failure-hunter|security-scan) role="review" ;;
  *) role="task" ;;
esac
if [ "$role" = "review" ]; then
  key="review:run"; cap="$MAX_REVIEW"
else
  slug="$(printf '%s' "$sub_desc" | grep -oE '\[task:[^]]+\]' | head -1 | sed 's/\[task:\(.*\)\]/\1/' || true)"
  [ -n "$slug" ] || slug="h$(printf '%s' "$sub_desc" | cksum | awk '{print $1}')"
  key="task:$slug"; cap="$MAX_RETRIES"
fi

# Read the current count for key, decide, then (if allowed) increment — all under the
# lock already held. Corrupt/missing ledger → treat as 0 (fail-open).
cur="$(HY_L="$ledger" HY_K="$key" python3 -c '
import os, json
try:
    d = json.load(open(os.environ["HY_L"]))
    print(int((d.get("items") or {}).get(os.environ["HY_K"], {}).get("n", 0)))
except Exception:
    print(0)
' 2>/dev/null || echo 0)"
case "$cur" in ''|*[!0-9]*) cur=0 ;; esac

if [ "$cur" -ge "$cap" ]; then
  if [ "$role" = "review" ]; then
    cat >&2 <<EOF
[hydraia] BLOCKED: circuit breaker — review cycles exhausted ($cur/$cap this run).

The review→fix loop has run its allotted cycles without converging. Do NOT dispatch
another review pass. STOP and surface the remaining findings to the human with the
evidence (which findings persist, what was tried). Raise the ceiling only if the human
decides: export HYDRAIA_MAX_REVIEW_CYCLES=3
EOF
  else
    cat >&2 <<EOF
[hydraia] BLOCKED: circuit breaker — task "$slug" exhausted its attempts ($cur/$cap).

This task has been retried its maximum times without landing. Do NOT re-dispatch it.
STOP and surface it as a genuine BLOCKER to the human with the evidence (no commit,
attempt count). Raise the ceiling only if the human decides:
  export HYDRAIA_MAX_TASK_RETRIES=3
EOF
  fi
  exit 2
fi

# Allow: increment the ledger count for this key (atomic tmp+rename).
HY_L="$ledger" HY_K="$key" HY_RID="$pm" python3 -c '
import os, json
p=os.environ["HY_L"]
try: d=json.load(open(p))
except Exception: d={}
if not isinstance(d,dict): d={}
d["runId"]=os.environ["HY_RID"]
items=d.setdefault("items",{})
it=items.setdefault(os.environ["HY_K"],{"n":0})
it["n"]=int(it.get("n",0))+1
tmp=p+".tmp"
json.dump(d,open(tmp,"w"))
os.replace(tmp,p)
' 2>/dev/null || true
```

Also extend `reset_if_new_run` (line ~92) to clear the ledger on a new run — add `: > "$adir/ledger.json" 2>/dev/null || true` next to the `dispatched`/`finished` resets. (An empty file parses as count 0 via the fail-open reader.)

- [ ] **Step 4: Run tests**

Run: `bash hooks/tests/run.sh`
Expected: breaker assertions PASS (0,0,2, stderr "breaker", bypass 0).

- [ ] **Step 5: Commit**

```bash
git add hooks/agents.sh hooks/tests/test-breaker.sh
git commit -m "feat(loop-hardening): circuit breaker — per-item attempt ledger in agents.sh"
```

---

## Task 6: Token caps + kill switch in agents.sh (Feature 2c)

**Files:**
- Modify: `hooks/agents.sh` (before the breaker block, right after the `HYDRAIA_ALLOW_DIRECT` allow at line 119)
- Test: `hooks/tests/test-caps.sh`

**Interfaces:**
- Consumes: `~/.cache/hydraia/telemetry.jsonl` (written by `summary.sh`), `hy_config`.
- Produces: blocks exit 2 on pause / over-cap.

- [ ] **Step 1: Write the failing tests**

```bash
# hooks/tests/test-caps.sh
REPO="$(git rev-parse --show-toplevel)"
mkdir -p "$REPO/docs/hydraia/.agents"; touch "$REPO/docs/hydraia/.active-plan"
P='{"hook_event_name":"PreToolUse","tool_name":"Task","cwd":"'"$REPO"'","tool_input":{"subagent_type":"hydraia-executor","description":"[task:x] x"}}'
# Kill switch blocks.
assert_exit 2 agents.sh "$P" HYDRAIA_PAUSE=1
assert_stderr "paused" agents.sh "$P" HYDRAIA_PAUSE=1
# Cap of 0 never blocks (default).
assert_exit 0 agents.sh "$P" HYDRAIA_DAILY_TOKEN_CAP=0
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash hooks/tests/run.sh`
Expected: FAIL — no pause/cap logic yet (`HYDRAIA_PAUSE=1` currently returns 0).

- [ ] **Step 3: Add the caps block to `agents.sh`**

Right after the existing `[ -n "${HYDRAIA_ALLOW_DIRECT:-}" ] && exit 0` (line 119), and BEFORE the breaker block from Task 5, insert:

```bash
# --- Kill switch + token caps ------------------------------------------------
# Kill switch: config loopPause or env HYDRAIA_PAUSE blocks ALL dispatch immediately.
PAUSED="false"; command -v hy_config >/dev/null 2>&1 && PAUSED="$(hy_config loopPause false HYDRAIA_PAUSE)"
if [ "$PAUSED" = "true" ] || [ -n "${HYDRAIA_PAUSE:-}" ]; then
  cat >&2 <<EOF
[hydraia] BLOCKED: loop paused (kill switch).

Sub-agent dispatch is disabled (loopPause / HYDRAIA_PAUSE). Switch to report-only.
Clear the pause to resume: unset HYDRAIA_PAUSE (or set loopPause=false in config).
EOF
  exit 2
fi

# Token caps (default 0 = off). Sum today's spend from the telemetry summary.sh writes.
DAILY_CAP="$(hy_config dailyTokenCap 0 HYDRAIA_DAILY_TOKEN_CAP 2>/dev/null || echo 0)"
RUN_CAP="$(hy_config perRunTokenCap 0 HYDRAIA_RUN_TOKEN_CAP 2>/dev/null || echo 0)"
case "$DAILY_CAP" in ''|*[!0-9]*) DAILY_CAP=0 ;; esac
case "$RUN_CAP" in ''|*[!0-9]*) RUN_CAP=0 ;; esac
TELEM="${HOME}/.cache/hydraia/telemetry.jsonl"
if { [ "$DAILY_CAP" -gt 0 ] || [ "$RUN_CAP" -gt 0 ]; } && [ -f "$TELEM" ]; then
  over="$(HY_T="$TELEM" HY_NOW="$now" HY_DC="$DAILY_CAP" HY_RC="$RUN_CAP" HY_RS="$pm" python3 -c '
import os
t=os.environ["HY_T"]; now=int(os.environ["HY_NOW"]); dc=int(os.environ["HY_DC"]); rc=int(os.environ["HY_RC"]); rs=int(os.environ.get("HY_RS") or 0)
import json
day=0; run=0
try:
    for line in open(t):
        try: r=json.loads(line)
        except Exception: continue
        ts=int(r.get("ts") or 0); tok=int(r.get("tokensIn") or 0)+int(r.get("tokensOut") or 0)
        if now-ts <= 86400: day+=tok
        if rs and ts>=rs: run+=tok
    if dc and day>=dc: print("daily "+str(day)+"/"+str(dc))
    elif rc and run>=rc: print("run "+str(run)+"/"+str(rc))
    else: print("")
except Exception:
    print("")
' 2>/dev/null || true)"
  if [ -n "$over" ]; then
    scope="${over%% *}"; nums="${over#* }"
    cat >&2 <<EOF
[hydraia] BLOCKED: token budget — ${scope} cap reached (${nums} tokens).

New sub-agent dispatch would exceed the configured ${scope} token cap. Switch to
report-only and surface where the run stands. The HUMAN raises the ceiling if warranted:
  export HYDRAIA_DAILY_TOKEN_CAP=…   (or HYDRAIA_RUN_TOKEN_CAP=…)
EOF
    exit 2
  fi
fi
```

- [ ] **Step 4: Run tests**

Run: `bash hooks/tests/run.sh`
Expected: caps assertions PASS (pause→2 + stderr "paused", cap 0→0). Breaker + blastgate tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/agents.sh hooks/tests/test-caps.sh
git commit -m "feat(loop-hardening): token caps + kill switch in agents.sh"
```

---

## Task 7: Constraints injection in preflight.sh (Feature 4)

**Files:**
- Modify: `hooks/preflight.sh` (before the final `exit 0`)
- Test: `hooks/tests/test-constraints.sh`

**Interfaces:**
- Consumes: `$hbase/constraints.md` (or `docs/hydraia/constraints.md`), `hy_config`.
- Produces: SessionStart `additionalContext` JSON on stdout when the file exists and `constraintsInject` is true.

- [ ] **Step 1: Write the failing test**

```bash
# hooks/tests/test-constraints.sh
REPO="$(git rev-parse --show-toplevel)"
CF="$REPO/docs/hydraia/constraints.md"
printf '# Constraints\n- Never edit auth/\n' > "$CF"
OUT="$(printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$REPO" | CLAUDE_PLUGIN_ROOT="$REPO" bash "$REPO/hooks/preflight.sh" 2>/dev/null || true)"
if printf '%s' "$OUT" | grep -q 'additionalContext' && printf '%s' "$OUT" | grep -q 'Never edit auth'; then
  PASS=$((PASS+1)); echo "  ok   preflight injects constraints"
else PASS=$((PASS)); FAIL=$((FAIL+1)); echo "  FAIL preflight constraints"; fi
rm -f "$CF"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash hooks/tests/run.sh`
Expected: FAIL — preflight emits no additionalContext yet.

- [ ] **Step 3: Add the injection block to `preflight.sh`**

In `hooks/preflight.sh`, just before the final `exit 0` (line 96), insert:

```bash
# --- 4. Binding constraints injection (SessionStart additionalContext) --------
# If the repo has a constraints.md, inject it as binding context for the whole session.
# Read via config so a repo can disable it. Fail-silent: never break SessionStart.
CINJECT="true"
command -v hy_config >/dev/null 2>&1 && CINJECT="$(hy_config constraintsInject true HYDRAIA_CONSTRAINTS)"
if [ "$CINJECT" = "true" ]; then
  croot="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$croot" ]; then
    cbase="$(cd "$croot" 2>/dev/null && hy_artifacts_dir 2>/dev/null)"; [ -n "$cbase" ] || cbase="$croot/docs/hydraia"
    cfile="$cbase/constraints.md"; [ -f "$cfile" ] || cfile="$croot/docs/hydraia/constraints.md"
    if [ -f "$cfile" ]; then
      CF="$cfile" python3 -c '
import os, json, sys
try:
    txt=open(os.environ["CF"]).read()[:8192]
    ctx="[hydraia binding constraints — read constraints.md; these rules are binding for this session]\n\n"+txt
    print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":ctx}}))
except Exception:
    sys.exit(0)
' 2>/dev/null || true
    fi
  fi
fi
```

- [ ] **Step 4: Run tests**

Run: `bash hooks/tests/run.sh`
Expected: constraints assertion PASS. All prior tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/preflight.sh hooks/tests/test-constraints.sh
git commit -m "feat(loop-hardening): inject constraints.md as SessionStart binding context"
```

---

## Task 8: Cost/spend line in summary.sh (Feature 2, reporting)

Add a spend-vs-cap line to the run summary so the human sees budget status. Optional/light — no new telemetry, reads what already exists.

**Files:**
- Modify: `hooks/summary.sh` (in the render section, after the Tokens line)

**Interfaces:**
- Consumes: the already-computed `tot_in`/`tot_out` in summary.sh's python; `hy_config` for the caps.

- [ ] **Step 1: Add a cap-aware line to the summary**

In `hooks/summary.sh`, the bash portion already resolves config. Before the python heredoc, add:

```bash
DAILY_CAP="$(hy_config dailyTokenCap 0 HYDRAIA_DAILY_TOKEN_CAP 2>/dev/null || echo 0)"
```

Then pass it into the python env (add `HY_DAILY_CAP="$DAILY_CAP"` to the `python3 -c` env list) and, in the render `lines` list right after the `Tokens:` line, add:

```python
try:
    _dc = int(os.environ.get("HY_DAILY_CAP", "0") or "0")
except Exception:
    _dc = 0
if _dc > 0:
    _spent = tot_in + tot_out
    lines.append(f"Budget:  {h(_spent)} this run · daily cap {h(_dc)}")
```

- [ ] **Step 2: Verify summary still renders (syntax check)**

Run: `bash -n hooks/summary.sh && python3 -c "print('summary bash+py ok')"`
Expected: `summary bash+py ok` (no bash syntax error). Full behavior is covered by an end-to-end run in Task 15's verification.

- [ ] **Step 3: Commit**

```bash
git add hooks/summary.sh
git commit -m "feat(loop-hardening): show run spend vs daily cap in run summary"
```

---

## Task 9: SKILL Phase -1 — autonomy tiers + cost estimate + early-exit (Features 5, 2a/2b)

**Files:**
- Modify: `skills/hydraia/SKILL.md` (Phase -1 section, after the intent table ~line 39)

**Interfaces:**
- Consumes: `patterns/cost.yaml`, `gate.yaml` (risk-path overlap).
- Produces: a tier + estimate presented to the human; feeds the Phase-3 review picker.

- [ ] **Step 1: Insert the tier + cost + noop subsection**

After the "Triage is ONE classification step…" paragraph (end of Phase -1, ~line 39), before "## Start-of-run guards", insert:

```markdown
### Autonomy tier + cost (after route, before the guards)

Once the route is chosen, estimate a **tier** from cheap signals and show a cost
estimate. This maps to hydraia's EXISTING controls — it adds no new enforcement axis.

**Early-exit (noop) first.** If the route's target is empty, do not spin the pipeline:
- `review` / `graph`: if `git diff --name-only` against the branch point is empty (or the
  named target does not exist), report "nothing to review", drop the run-complete marker
  (`printf 'brief\n' > <base>/.run-complete`), and stop. No Phases 0–6.
- `perf` / `db`: if the named symptom target is absent or already within a stated
  threshold, report and stop.

**Tier (feature-shaped routes).** Classify from: likely files touched, overlap with the
`gate.yaml` denylist (risk), new-logic vs mechanical, presence of UI surfaces:
- **Tier S (trivial):** no new logic, no new file, no risk-path, ≤ ~2 files → propose
  quick-mode (the `.quick-approved` path) or a Lite review. Minimal ceremony.
- **Tier M (standard):** default — full pipeline, Full review.
- **Tier L (large / risky):** many files, risk-path overlap, or a new service → full
  pipeline + all gates; the human may raise the agent ceiling.

**Cost estimate.** Read `patterns/cost.yaml` for the route × tier and state a one-line
token estimate (e.g. "≈200k tokens, Tier S"). It is a rough anchor, not a promise.

**Confirm once.** Present the tier + estimate in a single `AskUserQuestion`,
pre-selecting the review depth for the Phase-3 run-controls picker. The human confirms
with one tap or overrides. Honor `autoTier` config (`off` → always Tier M, today's
behavior). A tier NEVER removes the security floor (Phase 5 mandatory reviewers, threat
model) — Tier S only trims optional ceremony, exactly as quick-mode already does.
```

- [ ] **Step 2: Verify the anchor text exists and the edit is coherent**

Run: `grep -n "Autonomy tier + cost" skills/hydraia/SKILL.md && grep -n "Early-exit (noop)" skills/hydraia/SKILL.md`
Expected: both lines found.

- [ ] **Step 3: Commit**

```bash
git add skills/hydraia/SKILL.md
git commit -m "feat(loop-hardening): Phase -1 autonomy tiers + cost estimate + noop early-exit"
```

---

## Task 10: SKILL Phase 0 — read constraints as binding

**Files:**
- Modify: `skills/hydraia/SKILL.md` (Phase 0, in the "Honor the effective config" paragraph ~line 181)

- [ ] **Step 1: Add the constraints read**

At the end of the "Honor the effective config" paragraph (before item 0 "Dependency check"), append:

```markdown

**Binding constraints (read first).** If `docs/hydraia/constraints.md` (or the external
artifacts base's `constraints.md`) exists, read it and treat every rule as BINDING for
this run — it is the repo's own "we don't do it this way" ledger and overrides default
behavior (never the safety gates). The SessionStart hook already injected it as context;
reading it here guarantees the full file is honored even if that injection was truncated.
```

- [ ] **Step 2: Verify**

Run: `grep -n "Binding constraints (read first)" skills/hydraia/SKILL.md`
Expected: line found.

- [ ] **Step 3: Commit**

```bash
git add skills/hydraia/SKILL.md
git commit -m "feat(loop-hardening): Phase 0 reads constraints.md as binding"
```

---

## Task 11: SKILL Phase 4 — task-slug tag + ledger escalation

**Files:**
- Modify: `skills/hydraia/SKILL.md` (Phase 4, the dispatch + watchdog paragraphs ~line 542 and ~line 578)

- [ ] **Step 1: Require the `[task:<slug>]` dispatch tag**

In Phase 4's first paragraph ("Dispatch a fresh `hydraia-executor` subagent per task…"), append a sentence:

```markdown
Tag each executor dispatch's description with a machine-readable `[task:<slug>]` marker
(the same `<slug>` the executor uses for its heartbeat file). The circuit-breaker hook
(`hooks/agents.sh`) reads this tag to count per-task attempts; without it the breaker
falls back to a description hash and still counts, but the tag makes escalation precise.
```

- [ ] **Step 2: Wire the breaker into the watchdog escalation**

In the hung-agent watchdog bullet that ends "…that is a genuine BLOCKER: stop and surface it…", append:

```markdown
The attempt cap is now also a RUNTIME guarantee: `hooks/agents.sh` blocks the
(maxTaskRetries+1)-th dispatch of the same `[task:<slug>]` and tells you to stop. When
you see that block, do NOT keep retrying — read the ledger (`<base>/.agents/ledger.json`),
surface the task as a blocker with its attempt count and the missing-commit evidence, and
escalate to the human.
```

- [ ] **Step 3: Verify**

Run: `grep -n "\[task:<slug>\]" skills/hydraia/SKILL.md`
Expected: at least two matches.

- [ ] **Step 4: Commit**

```bash
git add skills/hydraia/SKILL.md
git commit -m "feat(loop-hardening): Phase 4 task-slug tag + breaker escalation"
```

---

## Task 12: SKILL Phase 5 — mechanized re-review cap

**Files:**
- Modify: `skills/hydraia/SKILL.md` (Phase 5, item 4 "Dedup before you triage…" ~line 679)

- [ ] **Step 1: Make the re-review cap point at the breaker**

In Phase 5 item 4, the sentence "Re-review only the changed surface if fixes were substantial (max one re-review cycle)." — extend it:

```markdown
Re-review only the changed surface if fixes were substantial (max `maxReviewCycles`
cycles, default 2). This cap is now enforced: `hooks/agents.sh` blocks a reviewer
dispatch past the cap for this run. If you hit that block, STOP re-reviewing — surface
the persisting findings to the human with what was tried, rather than looping.
```

- [ ] **Step 2: Verify**

Run: `grep -n "maxReviewCycles" skills/hydraia/SKILL.md`
Expected: line found.

- [ ] **Step 3: Commit**

```bash
git add skills/hydraia/SKILL.md
git commit -m "feat(loop-hardening): Phase 5 mechanized re-review cap (maxReviewCycles)"
```

---

## Task 13: doctor.sh — validate gate.yaml presence (light)

**Files:**
- Modify: `hooks/doctor.sh` (in its `--check` output path)

- [ ] **Step 1: Add a gate.yaml presence note**

Find the section in `hooks/doctor.sh` that prints repo/config diagnostics (the `--check` branch). Add a check that prints, for the current repo:

```bash
# Loop-hardening artifacts (informational; all optional/opt-in).
_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$_root" ]; then
  [ -f "$_root/gate.yaml" ] && echo "  gate.yaml: present" || echo "  gate.yaml: absent (built-in denylist default in use)"
  _cb="$(cd "$_root" 2>/dev/null && hy_artifacts_dir 2>/dev/null)"; [ -n "$_cb" ] || _cb="$_root/docs/hydraia"
  [ -f "$_cb/constraints.md" ] && echo "  constraints.md: present (injected each session)" || echo "  constraints.md: absent (copy constraints.sample.md to enable)"
fi
```

Place it where doctor already prints per-repo info; if doctor.sh has no natural spot, add a small `hy_loop_hardening_status` function and call it in `--check`. Keep it purely informational — doctor must not fail on absence (all are optional).

- [ ] **Step 2: Verify doctor still runs**

Run: `bash hooks/doctor.sh --check >/dev/null 2>&1; echo "exit=$?"`
Expected: `exit=0` (or doctor's normal check exit) — no crash. If doctor's `--check` needs args, run its documented no-op invocation instead and confirm the new lines appear.

- [ ] **Step 3: Commit**

```bash
git add hooks/doctor.sh
git commit -m "feat(loop-hardening): doctor reports gate.yaml/constraints presence"
```

---

## Task 14: Codex parity checklist artifact

**Files:**
- Create: `docs/hydraia/specs/loop-hardening-codex-parity.md`

**Interfaces:**
- The interface to the parallel Codex session. Does NOT edit `codex/`.

- [ ] **Step 1: Write the checklist**

```markdown
# Loop-Hardening — Codex Parity Checklist

The Claude side of loop-hardening (spec `2026-08-19-loop-hardening-design.md`) is
implemented in `hooks/` + `skills/hydraia/SKILL.md`. The Codex port must mirror it under
`codex/`. Data files are SHARED (read as-is); only the hook LOGIC is duplicated.

## Shared data (read directly, do NOT duplicate)
- [ ] `gate.yaml` — blastgate denylist/maxFiles.
- [ ] `docs/hydraia/constraints.md` (or `$hbase/constraints.md`) — binding constraints.
- [ ] `$hbase/.agents/ledger.json` — breaker attempt counts.
- [ ] `patterns/cost.yaml` — cost anchors.
- [ ] `loop-budget.md` — human budget doc.
- [ ] New config keys in `~/.config/hydraia/config.json` (Codex `config.sh` uses the same `hy_config` contract).

## Duplicated logic (new Codex files, same behavior, Codex hook I/O schema)
- [ ] `codex/hooks/blastgate.sh` — port `hooks/blastgate.sh`; read Codex payload (apply_patch args + shell write path), same gate.yaml, same block contract (exit 2 + JSON).
- [ ] Breaker in the Codex agents-budget hook — port the ledger block from `hooks/agents.sh`; resolve slug from the Codex executor spawn args (`[task:<slug>]` tag carried in the agent prompt).
- [ ] Token caps + kill switch in the Codex agents-budget hook — same telemetry read (`~/.cache/hydraia/telemetry.jsonl`), same `loopPause`/`HYDRAIA_PAUSE`.
- [ ] Constraints injection in `codex/hooks/preflight.sh` — same file, Codex additionalContext mechanism.
- [ ] `codex/setup.sh` — install `blastgate.sh` into `~/.codex` and wire it in `~/.codex/hooks.json` alongside the gate.

## Shared PIPELINE CONTRACT (keep byte-identical, CI drift check)
- [ ] Phase -1 tier + cost + noop block.
- [ ] Phase 0 "Binding constraints (read first)" paragraph.
- [ ] Phase 4 `[task:<slug>]` tag + breaker escalation.
- [ ] Phase 5 `maxReviewCycles` re-review cap.
Copy these blocks verbatim from `skills/hydraia/SKILL.md` into `codex/skills/hydraia/SKILL.md`.

## Config keys the Codex `config.sh` must recognize
`pathGate`, `maxFilesEnforce`, `constraintsInject`, `maxReviewCycles`, `dailyTokenCap`, `perRunTokenCap`, `loopPause`, `autoTier` (+ env homologs). All via the existing `hy_config` contract — no schema change, just honored by the Codex hooks.
```

- [ ] **Step 2: Commit**

```bash
git add docs/hydraia/specs/loop-hardening-codex-parity.md
git commit -m "docs(loop-hardening): Codex parity checklist for the parallel port"
```

---

## Task 15: README + CHANGELOG + full verification

**Files:**
- Modify: `README.md`, `README.es.md`, `CHANGELOG.md`

- [ ] **Step 1: Run the full hook test suite**

Run: `bash hooks/tests/run.sh`
Expected: `N passed, 0 failed` covering blastgate, breaker, caps, constraints.

- [ ] **Step 2: Sanity-check every hook parses**

Run: `for h in gate blastgate agents preflight summary plancheck config; do bash -n "hooks/$h.sh" && echo "$h ok"; done`
Expected: `ok` for all seven.

- [ ] **Step 3: Add a Loop-Hardening section to `README.md`**

Add under the existing features/hooks documentation:

```markdown
### Loop-Hardening (v0.16)

Five runtime guarantees adapted from loop-engineering:
- **Blast-radius gate** (`gate.yaml`): blocks edits to secrets/auth/payments/migrations. `pathGate=off` to disable; `HYDRAIA_ALLOW_DIRECT=1` to bypass (human).
- **Circuit breaker**: caps per-task retries (`maxTaskRetries`) and review cycles (`maxReviewCycles`), then escalates instead of looping.
- **Token caps + kill switch**: `dailyTokenCap` / `perRunTokenCap` (default off) and `HYDRAIA_PAUSE=1` stop sub-agent dispatch.
- **Binding constraints**: copy `docs/hydraia/constraints.sample.md` to `constraints.md`; it is injected as binding context every session.
- **Autonomy tiers**: Phase -1 estimates a size/risk tier + token cost and pre-selects review depth.
```

- [ ] **Step 4: Mirror the section in `README.es.md`** (Spanish translation of the same block).

- [ ] **Step 5: Add a CHANGELOG entry**

```markdown
## [0.16.0] - 2026-08-19
### Added
- Loop-Hardening: blast-radius path gate (gate.yaml), circuit breaker (per-item attempt ledger), token caps + kill switch, binding constraints injection, and Phase -1 autonomy tiers + cost estimate. Shared data files are Codex-port compatible (see loop-hardening-codex-parity.md).
```

- [ ] **Step 6: Commit**

```bash
git add README.md README.es.md CHANGELOG.md
git commit -m "docs(loop-hardening): README (EN/ES) + CHANGELOG 0.16.0"
```

- [ ] **Step 7: Final verification — a live gate proof**

Run (proves blastgate fires end-to-end in this repo):
```bash
printf '{"tool_input":{"file_path":"%s/auth/secret.ts"}}' "$(git rev-parse --show-toplevel)" | bash hooks/blastgate.sh; echo "exit=$?"
```
Expected: the "BLOCKED: blast-radius gate" message on stderr and `exit=2`.

---

## Self-Review notes (author)

- **Spec coverage:** Feature 1 → Tasks 5, 11, 12. Feature 2 → Tasks 1(cost.yaml,budget), 6, 8, 9(2a/2b). Feature 3 → Tasks 1(gate.yaml), 3, 4, 13. Feature 4 → Tasks 1(sample), 7, 10. Feature 5 → Task 9. Codex parity → Task 14. Config table → Tasks 3,5,6,7,9. Testing → Tasks 2,3,5,6,7,15.
- **No new deps:** all parsing via python3 (existing prerequisite); pyyaml NOT required (hooks hand-parse gate.yaml).
- **Ordering:** data (1) → harness (2) → security hook (3,4) → breaker (5) → caps (6) → constraints (7) → reporting (8) → SKILL prose (9–12) → doctor (13) → codex checklist (14) → docs+verify (15). Each task ends green and committable.
- **maxReviewCycles / maxTaskRetries** names are consistent across Tasks 5, 11, 12 and the config table.
- **Every hook stays fail-open + opt-in + env-bypass** per Global Constraints.
```
