## Phase 5 — Review → triage → bounded fix

The goal of review is a **verified, finite** set of real defects — not the longest
list of findings. Every unverified finding that reaches a fix costs a loop; every fix
grows code that grows findings. This phase is built to converge.

### 1. Stage the diff (a file, never pasted)

Write the unified diff of everything since the run's base (`git merge-base` with the
base branch, or the commit recorded when the plan was armed) — untracked files included —
to a temp file, e.g. `git diff <base>... > "$TMPDIR/hydraia-<run>.diff"`. With
auto-commit OFF, diff the working tree (staged + unstaged). Reviewers get the **path**;
the diff text never goes into a prompt or into your context in full. Judge against the
diff, not against executor reports.

### 2. Review panel — scaled by level, scoped to the diff

Honor the review depth from the level (recorded in the run log). Read
`git diff --name-only` first and dispatch only what the diff warrants:

- **Always — the floor (never removable, not customizable):** `hydraia-reviewer`
  (Opus — the judge) + `security-scan`. **At Levels 2–3 the floor adds**
  `security-reviewer` (Opus) and `silent-failure-hunter` (Sonnet). (Level 1 is by rule a
  change with no security surface; if one appears, the run re-levels to 2+ and the full
  floor applies.)
- **Level 2 (Lite):** + the ONE language/framework reviewer matching the diff's main
  file type (`typescript-reviewer`, `react-reviewer`, `python-reviewer`, `go-reviewer`,
  `java-reviewer`, `csharp-reviewer`, `vue-reviewer`, `angular-reviewer`,
  `database-reviewer` for SQL/migrations). Sonnet.
- **Level 3 (Full):** + every language reviewer the diff touches, `security-review`
  (OWASP pass), stack security skills (**springboot-security**, **django-security**),
  and `type-design-analyzer` / `performance-optimizer` only when the diff's nature
  (new public types, hot paths) warrants them. Sonnet.
- **Level 1:** the judge + `security-scan` only.

Every reviewer is launched with: the diff path, the spec path (the judge only — other
reviewers review the code blind, so they are not anchored by the spec's claims), and the
instruction to return **compact findings** — one block per finding,
`file:line — what goes wrong — evidence — smallest fix`, no severity labels, no style
nits, `No verified findings.` when clean. Launch them in one wave; read nothing until
all have returned. Generic agents always get an explicit `model` (see Model policy).

**Reviewer panel customization.** Read `customize.toml` `[[reviewers]]` (repo > global >
shipped). Entries merge **by `id`** (matching `id` replaces a shipped pass-2 layer, a new
`id` appends, `instruction = ""` disables it). This applies to the optional layers only —
the security floor above always runs. Unparseable override → warn, use the shipped panel.

### 3. Triage — verify, then one verdict per finding

**Carry forward first.** If the spec's `## Review Triage Log` already has rows (a
loopback or resumed run), check each new finding against them: same location + same
claim + the code still reads as the row describes → keep the row's verdict and route,
record it again as `carried`, skip verification, and **never patch or defer it again**.
This is what stops the same finding from being re-litigated on every pass.

Then, for every other finding (ignore any severity a reviewer assigned — you grade):

- **Verify the claim at the cited line.** Read past the changed lines — callers, guards
  upstream — until you can say whether the bad outcome actually occurs. A different
  problem nearby does not settle this one. Code that fails loudly on a state nobody
  showed is reachable is correct, not a bug. A failure that exists in the Phase-0
  baseline is pre-existing — not this change's defect.
- **Exactly one verdict:** `high` (intolerable) · `medium` (tolerable) · `low` (cosmetic
  or negligible) — the outcome is real, graded by harm to users or developers (for
  developer-only harm, name which caller diverges or which rule erodes; "messy" with no
  named harm is not a grade) · `false` — you checked and it does not happen (write what
  disproves it) · `maybe-false` — the code cannot settle it (write what would).
- Log **every** finding as one row in the spec's `## Review Triage Log`: verdict +
  one-sentence evidence. Never drop one silently.
- **Reject** `false`. **Reject** `low` when users/developers would rarely meet it and the
  fix adds anything beyond a direct correction (guards, branches, parameters).
  **Reject** any finding whose fix is "edit the spec" unless it is an intent gap.
- **Group** the survivors by shared root cause (same defect produced both — not merely
  the same file or the same fix). A group carries its highest verdict.

### 4. Route — cascade, and only real defects enter the fix loop

Route each group to exactly one of:

- **`intent_gap`** — caused by the change, but the frozen intent does not settle the
  right behaviour (more than one reasonable reading). **Ask the human** — one question
  with the options. Record the answer inside `<frozen-after-approval>` as a decision.
- **`bad_spec`** — caused by the change, including deviations from the spec, and the
  non-frozen spec (Code Map, Design, a plan task) should have prevented it. **Do not
  patch on top.** Extract **KEEP** notes (what worked and must survive), revert the
  affected code, amend the spec/plan task, append to `## Spec Change Log` (trigger,
  what changed, the known-bad state to avoid, KEEP), and re-dispatch those tasks
  (Phase 4 rules). When unsure between `bad_spec` and `patch`, prefer `bad_spec` — a
  spec-level fix produces coherent code; stacked patches do not.
- **`patch`** — caused by the change, and the smallest fix is trivial, adds no public
  surface, and guards no state you did not show is reachable.
- **`defer`** — pre-existing (not caused by this change); or every member is
  `maybe-false` and would be `medium`/`high` if true (record as unverified + what
  would settle it); or the fix edits agent-context files (CLAUDE.md, AGENTS.md, rules).
  Append to `<base>/deferred-work.md` (`source`, one-sentence summary, evidence). A
  verified `high` **security** finding is never deferred.

**Cascade.** If any `intent_gap` or `bad_spec` exists, resolve those first — code will be
re-derived, so `patch` entries in the same area are moot. Only `high`/`medium` patches
enter the fix loop; a `low` survives only if its fix is a one-line correction.

### 5. Fix — through an executor, counted, bounded

- **You never edit source in this phase.** Fixes go to an executor: prefer re-engaging
  the same executor that built the code (SendMessage, when available); otherwise
  dispatch a fresh `hydraia-executor` (Sonnet) whose description carries
  `[fix:<slug>]`. The message is exactly the verified list —
  `file — what is wrong — what the smallest fix must do` — plus: *"Run only the tests
  that cover the files you edit — nothing wider. Reply with what you changed."*
- `hooks/agents.sh` counts `[fix:]` dispatches: `maxFixAttempts` (2) per finding and
  `maxFixDispatches` (6) per run. The verify-loop hook stops the same failure at 3.
  When a breaker blocks, do not work around it: the run ends `BLOCKED` with the open
  findings, what each attempt tried, and the evidence.
- After fixes: run the spec's `## Verification` commands yourself (foreground), rewrite
  the diff file, and **re-review only the changed surface, and only if a `high`/`medium`
  or a `bad_spec` re-derivation happened** — the judge pass only, not the whole panel.
  At most `maxReviewCycles` (2) cycles, enforced by `hooks/agents.sh` on the judge's
  dispatches. Past it: stop and surface the remaining findings to the human.

### 6. Hunt gamed verification (before accepting "all green")

Scan the diff for the ways a green build lies: weakened or deleted tests, loosened
assertions (`expect(x ?? D).toBe(D)`), snapshot-only / no-throw-only checks, mock-only
tests that never exercise the real path, swallowed exceptions / empty catches /
`except: pass`, errors downgraded to warnings or silent fallbacks, and lint/type/build
config edited to disable a rule (`.eslintrc`, `biome.json`, `.ruff.toml`, `tsconfig`
`strict`/`skipLibCheck`, `# type: ignore`, `@ts-nocheck`, `--no-verify`). Each is a
finding, routed like any other — a fixed-to-look-fixed change is worse than an obvious
failure.



## NEXT

Read fully and follow `phases/phase-6-verify.md`.
