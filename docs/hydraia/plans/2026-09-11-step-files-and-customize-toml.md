# Plan — Step-file pipeline + `customize.toml`

**Goal:** Fragment `skills/hydraia/SKILL.md` (806 lines) into a dispatcher +
`phases/*.md` loaded JIT, mirror per-phase to Codex with real CI parity, and add
a `customize.toml` override layer (executor model/handoff + Phase-5 reviewer
panel) read by the orchestrator.

**Spec:** `docs/hydraia/specs/2026-09-11-step-files-and-customize-toml-design.md`

**Architecture:** dispatcher holds always-loaded global facts (route→phase map,
autonomy tiers, model-policy pointer) + JIT loader rule; phase bodies moved
verbatim into `phases/*.md`; Codex mirrors byte-identical; overrides consumed by
the orchestrator only (no bash TOML parser).

**Tech stack:** Markdown skill files, bash hooks, TOML config, GitHub Actions CI.

## Global Constraints

- Phase bodies move **verbatim**. Any wording change is a separate commit with a
  one-line note. After extraction, `cat` of phase files in order must equal the
  old contract text (normalized-whitespace diff clean).
- Codex `phases/*.md` byte-identical to Claude `phases/*.md` (CI `diff -q`).
- No AI attribution in commits (repo rule). No `Co-Authored-By` trailer.
- Do not weaken security gate, spec-drive gate, or loop-hardening.
- Hooks stay fail-open + runtime-dependency-free.
- Commit per task; verify each lands in git before the next.

## File Structure

```
skills/hydraia/SKILL.md            # → dispatcher (rewritten)
skills/hydraia/phases/             # NEW: 11 phase files
skills/hydraia/customize.toml      # NEW: shipped defaults
codex/skills/hydraia/SKILL.md      # → dispatcher + translation table (rewritten)
codex/skills/hydraia/phases/       # NEW: byte-identical mirror
hooks/doctor.sh                    # + customize presence report
.github/workflows/ci.yml           # + per-phase parity diff, + customize.toml TOML validate
README.md / README.es.md / CHANGELOG.md  # docs
```

Phase-file split map (current `skills/hydraia/SKILL.md` line ranges):

| File | Source lines | Header |
|---|---|---|
| (dispatcher keeps) | 1–15 | frontmatter + title/preamble |
| `phases/phase--1-triage.md` | 16–40 | `## Phase -1 — Intent triage` |
| `phases/autonomy-tier.md` | 41–69 | `### Autonomy tier + cost` |
| `phases/guards.md` | 70–197 | `## Start-of-run guards` |
| `phases/model-policy.md` | 198–207 | `## Model policy` (also summarized always-loaded in dispatcher) |
| `phases/phase-0-context.md` | 208–278 | `## Phase 0 — Context` |
| `phases/phase-1-think.md` | 279–287 | `## Phase 1 — Think` |
| `phases/phase-2-design.md` | 288–375 | `## Phase 2 — Design + threat model` |
| `phases/phase-3-plan.md` | 376–574 | `## Phase 3 — Plan + self-review` |
| `phases/phase-4-execute.md` | 575–671 | `## Phase 4 — Execution` |
| `phases/phase-5-review.md` | 672–726 | `## Phase 5 — Code review` |
| `phases/phase-6-verify.md` | 727–798 | `## Phase 6 — Verify & close` |
| `phases/token-discipline.md` | 799–806 | `## Token discipline` |

> Note: `-1-triage` + `autonomy-tier` are one logical phase; keep as two files or
> merge into `phase--1-triage.md` — decide at extraction by cohesion. Codex source
> ranges differ (offsets ~13 lines earlier, contract 38–773); split by the SAME
> headers, not by line number.

## Task 1 — Extract Claude phase files (verbatim)

**Files:**
- Create: `skills/hydraia/phases/*.md` (11 files per the split map)
- Modify: `skills/hydraia/SKILL.md` → dispatcher
- Test: `bash` verification below

**Interfaces:** Produces phase files consumed by the dispatcher's JIT loader.

- [ ] Read `skills/hydraia/SKILL.md` fully. For each row in the split map, move
      that section **verbatim** (heading included) into its phase file.
- [ ] Rewrite `SKILL.md` as the dispatcher. Keep frontmatter (name/description)
      unchanged. Body = preamble + these always-loaded global facts, then the
      loader. Dispatcher body template:

  ```markdown
  # Hydraia — Agentic Development Pipeline

  This skill drives a fixed 7-phase pipeline. **Step-file architecture:** read one
  phase file fully, execute it, then load the next only when its `## NEXT` says to.
  **NEVER load two phase files at once.** Do not skip, reorder, or pre-load phases.

  ## Always-loaded facts (carry these the whole run)

  - **Route → phases** (from Phase -1 triage):
    feature 0–6 · plan 0–3 (stop) · story -1–3 · perf/db -1–6 · architect -1–6 ·
    review 5–6 · graph (codegraph only).
  - **Autonomy tiers:** S/M/L from files-touched, gate.yaml risk overlap,
    new-logic-vs-mechanical, UI presence → maps to review depth + ceremony.
    `autoTier=off` → always Tier M. Never removes the security floor.
  - **Model policy:** this orchestrator session stays Opus 4.8 for judgment
    (triage/design/plan/review); execution delegates to the Phase-4 executor
    (default Sonnet, overridable via customize.toml). Full policy:
    `phases/model-policy.md`.
  - **Customize:** before Phase 4 read `[executor]` and before Phase 5 read
    `[[reviewers]]` from customize.toml (see phase bodies). The security gate is
    NOT customizable.

  ## FIRST STEP

  Read fully and follow `phases/phase--1-triage.md`.
  ```

- [ ] Add a `## NEXT` pointer at the end of every phase file pointing to the next
      phase file by relative path (e.g. `phase-0-context.md` → `## NEXT: read
      phases/phase-1-think.md`). Preserve any conditional routing already in the text.
- [ ] **Verify verbatim:** run and confirm empty diff (ignoring the added NEXT
      pointers and the dispatcher preamble):
  ```bash
  cd /Users/jdanigo/Documents/GitHub/hydraia
  # concatenated phase bodies should contain every original section heading
  for h in "Phase -1 — Intent triage" "Start-of-run guards" "Model policy" \
    "Phase 0 — Context" "Phase 1 — Think" "Phase 2 — Design" "Phase 3 — Plan" \
    "Phase 4 — Execution" "Phase 5 — Code review" "Phase 6 — Verify" "Token discipline"; do
    grep -rq "$h" skills/hydraia/phases/ || echo "MISSING: $h"
  done
  echo "SKILL.md dispatcher line count:"; wc -l skills/hydraia/SKILL.md
  ```
  Expect: no `MISSING:` lines; dispatcher ≤ ~120 lines.
- [ ] Commit: `refactor(skill): split SKILL.md into dispatcher + phases/ (JIT loading)`

## Task 2 — Wire executor + reviewer customize reads into phase bodies

**Files:**
- Modify: `skills/hydraia/phases/phase-4-execute.md`, `skills/hydraia/phases/phase-5-review.md`

**Interfaces:** Consumes `customize.toml` `[executor]` / `[[reviewers]]`.

- [ ] In `phase-4-execute.md`, before the dispatch instruction, insert:
  ```markdown
  ### Executor customization (read before dispatch)

  Read the effective customize config (repo `<artifacts-base>/custom/hydraia.toml`
  > global `~/.config/hydraia/custom/hydraia.toml` > shipped
  `skills/hydraia/customize.toml`), merging per its header rules. If any override
  is unparseable, warn and fall back to shipped defaults.

  - `[executor].model` — dispatch each `hydraia-executor` on this model (pass it
    as the model at launch, overriding the agent's `sonnet` default). Default `sonnet`.
  - `[executor].handoff` — if non-empty, follow it verbatim as the dispatch recipe
    (substitute `{task_block}`, `{graph_context}`), instead of the default subagent
    dispatch. Runs under the same blast-gate + spec-drive hooks.
  ```
- [ ] In `phase-5-review.md`, before building the pass-2 panel, insert:
  ```markdown
  ### Reviewer panel customization (read before pass 2)

  Read customize `[[reviewers]]` (merged by `id`: matching id replaces a shipped
  layer, new id appends, `instruction = ""` disables that id). Apply to the pass-2
  panel only. **The always-on security gate (`security-scan` + `security-review`,
  plus stack security reviewers) is NOT customizable and always runs** regardless
  of this config.
  ```
- [ ] Verify both inserts present; security-non-customizable sentence present in
      `phase-5-review.md`.
- [ ] Commit: `feat(skill): phase-4/5 read customize.toml for executor model + reviewer panel`

## Task 3 — Ship `customize.toml` defaults

**Files:**
- Create: `skills/hydraia/customize.toml`

- [ ] Write the file verbatim:
  ```toml
  # DO NOT EDIT — overwritten on every plugin update.
  # Override in <artifacts-base>/custom/hydraia.toml (repo) or
  # ~/.config/hydraia/custom/hydraia.toml (global).
  # Merge: strings replace · lists append · tables merge key-by-key ·
  # arrays-of-tables merge by `id` (matching id replaces, new id appends).
  # Unknown keys/tables are ignored (forward-compatible).

  [executor]
  # Model the Phase-4 executor runs on. Drop to "haiku" for mechanical work,
  # keep "sonnet" (default), or use handoff to route elsewhere.
  model = "sonnet"

  # Full override of the dispatch recipe. Empty = default subagent dispatch
  # (fresh hydraia-executor per task, task block + graph context only).
  # {task_block} and {graph_context} substituted at run time.
  handoff = ""

  # Phase-5 pass-2 reviewer panel. Array-of-tables merged by id. Omit to keep the
  # shipped panel. instruction = "" disables a shipped layer by id.
  # The security gate is separate and always runs — it is not listed here.
  # [[reviewers]]
  # id = "correctness"
  # model = "opus"
  # instruction = ""

  # Reserved for a later version (ignored today):
  # [workflow]
  # activation_steps = []
  # persistent_facts = []
  # on_complete = ""
  ```
- [ ] Validate: `python3 -c "import tomllib;tomllib.load(open('skills/hydraia/customize.toml','rb'));print('OK')"`
- [ ] Commit: `feat(config): ship customize.toml defaults (executor + reviewer overrides)`

## Task 4 — Mirror phase files to Codex (byte-identical)

**Files:**
- Create: `codex/skills/hydraia/phases/*.md`
- Modify: `codex/skills/hydraia/SKILL.md` → dispatcher (translation table + contract markers around loader)

- [ ] Copy each `skills/hydraia/phases/X.md` to `codex/skills/hydraia/phases/X.md`
      byte-identical:
  ```bash
  cd /Users/jdanigo/Documents/GitHub/hydraia
  mkdir -p codex/skills/hydraia/phases
  cp skills/hydraia/phases/*.md codex/skills/hydraia/phases/
  ```
- [ ] Rewrite `codex/skills/hydraia/SKILL.md`: keep the existing **host
      translation table** (Claude→Codex mechanics) above the contract, then wrap
      the dispatcher loader between `<!-- BEGIN PIPELINE CONTRACT -->` and
      `<!-- END PIPELINE CONTRACT -->`. The loader points to `phases/*.md`
      (Codex reads them through the translation table). Preserve the invocation
      note (`$hydraia`) and any Codex-only guidance already present.
- [ ] Verify byte-identity: `diff -rq skills/hydraia/phases codex/skills/hydraia/phases`
      (expect no output).
- [ ] Verify contract markers present + non-empty:
  ```bash
  awk '/BEGIN PIPELINE CONTRACT/{f=1;next}/END PIPELINE CONTRACT/{f=0}f' \
    codex/skills/hydraia/SKILL.md | grep -q . && echo "contract OK"
  ```
- [ ] Commit: `refactor(codex): mirror phase files + dispatcher, byte-identical to Claude`

## Task 5 — CI: per-phase parity + customize.toml validation

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] In the `codex-parity` job, after the existing "Pipeline contract present"
      step, add:
  ```yaml
      - name: Per-phase parity (Claude == Codex)
        run: |
          set -euo pipefail
          diff -rq skills/hydraia/phases codex/skills/hydraia/phases
          echo "phase files byte-identical across hosts"
      - name: customize.toml valid
        run: |
          python3 -c "import tomllib;tomllib.load(open('skills/hydraia/customize.toml','rb'));print('OK customize.toml')"
  ```
- [ ] Validate YAML: `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/ci.yml'))" 2>/dev/null || python3 -c "import json,sys;print('yaml lib absent, skip')"`
      (best-effort; the diff/toml steps are the substantive check).
- [ ] Commit: `ci: enforce per-phase Claude↔Codex parity + validate customize.toml`

## Task 6 — doctor.sh + docs

**Files:**
- Modify: `hooks/doctor.sh`, `README.md`, `README.es.md`, `CHANGELOG.md`

- [ ] In `doctor.sh`, near the gate.yaml/constraints.md presence report
      (`hooks/doctor.sh:183-189`), add a read-only report of customize overrides:
  ```bash
  # customize.toml overrides (presence only — not parsed)
  for f in "$(hy_artifacts_dir 2>/dev/null)/custom/hydraia.toml" \
           "$HOME/.config/hydraia/custom/hydraia.toml"; do
    [ -f "$f" ] && echo "  customize override: $f"
  done
  echo "  customize defaults: skills/hydraia/customize.toml"
  ```
  (Adapt to doctor.sh's actual echo/format style and its `hy_artifacts_dir` usage.)
- [ ] `README.md` + `README.es.md`: document (a) step-file architecture in the
      pipeline/skill section, (b) `customize.toml` — the override files, precedence,
      the `[executor] model = "haiku"` example, the reviewer panel, and that the
      security gate is not customizable.
- [ ] `CHANGELOG.md`: add an Unreleased entry summarizing both features.
- [ ] Commit: `docs: document step-file architecture + customize.toml (EN/ES + doctor + changelog)`

## Verification (whole change)

- [ ] `diff -rq skills/hydraia/phases codex/skills/hydraia/phases` → empty.
- [ ] `python3 -c "import tomllib;tomllib.load(open('skills/hydraia/customize.toml','rb'))"` → OK.
- [ ] All original phase headings present under `skills/hydraia/phases/` (Task 1 grep).
- [ ] `wc -l skills/hydraia/SKILL.md` ≤ ~120.
- [ ] `bash -n hooks/doctor.sh` clean.
- [ ] `python3 -m json.tool codex/hooks.json >/dev/null` still OK (untouched, sanity).
- [ ] Read-through: dispatcher → phase--1 → … → phase-6 chain has valid `## NEXT`
      pointers; no phase references another by "see spec"/dangling path.
- [ ] `security-scan`/`security-review` still described as always-on and
      non-customizable in `phase-5-review.md`.

---

## Increment 2 — execution routing + brainstorming right-sizing (implemented)

- [x] Task 7 — `Exec class` per task in `phase-3-plan.md`; routing picker (step 6c) with
      recommendation + per-option cost/gets + hand-off stop.
- [x] Task 8 — `phase-4-execute.md` per-class routing table + application + cheap-model
      fallback note.
- [x] Task 9 — `customize.toml` `[executor].routing` + `[executor.by_class]`; validated TOML.
- [x] Task 10 — `patterns/cost.yaml` `models` weights + `routing_bands`.
- [x] Task 11 — dispatcher routing fact (Claude + Codex); phases re-mirrored byte-identical.
- [x] Task 12 — `brainstorming` Spike/Bounded/Architectural + mid-task upgrade (spec always written).
- [x] Task 13 — CHANGELOG increment-2 entries.

### Verification (increment 2)
- [x] `customize.toml` valid TOML with `[executor].routing` + `[executor.by_class]`.
- [x] phases Claude==Codex byte-identical after re-mirror.
- [x] codex contract block present after dispatcher edits.
- [x] `Exec class` + routing table present in phase-3/phase-4.
- [x] brainstorming has Spike/Bounded/Architectural + mid-task upgrade.
