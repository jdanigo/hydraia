## Start-of-run guards (before Phase 0)

**Language gate (first action, before anything else).** Call the
`AskUserQuestion` tool once to ask which language the user wants **replies** in —
options: `English` and `Español`. Use the answer for all user-facing communication
for the rest of the run: narration, the Phase-1 clarifying question, review
findings, and the final summary. If the user dismisses the question, default to the
language they wrote their request in. This choice does NOT change code, commit
messages, spec/plan files, or the credits line — those stay as-is (English,
portable). Ask this exactly once per run; `/hydraia:resume` inherits the prior
run's choice if the run log records it, otherwise re-asks.

**Storage & commit gate (second action, right after the Language gate).** Two
`AskUserQuestion` prompts, asked once per run (like the language gate). Do NOT
recommend an option — the user chooses; these are privacy/workflow decisions, not
quality ones.

1. **Artifacts location** — "Where should Hydraia store its artifacts (specs, plans,
   QA, run logs, and pipeline state)?"
   - `In the repo` → `<repo>/docs/hydraia/` (tracked by git — the default).
   - `Outside the repo` → `~/.config/hydraia/artifacts/<repo-slug>/` (on this machine,
     never committed, no `.gitignore` edits). `<repo-slug>` = repo dir basename + `-`
     + the first 6 hex of a hash of the absolute repo root.
2. **Auto-commit** — "Auto-commit each task as Hydraia goes?"
   - `Yes` → commit per task (the default).
   - `No` → executors do NOT commit; all changes are left in the working tree for you
     to commit as you like.

After the answers: persist both to the GLOBAL config `~/.config/hydraia/config.json`
under `repos["<absolute repo root>"]` — do NOT hand-edit that JSON. Use the
`hy_config_set` helper in `hooks/config.sh`, which merges into the file atomically,
preserving every other repo and key:

```bash
bash -c '. "$CLAUDE_PLUGIN_ROOT/hooks/config.sh"
hy_config_set "<absolute repo root>" artifactsDir "<docs/hydraia | absolute external path>"
hy_config_set "<absolute repo root>" autoCommit "<true|false>"'
```

Pass `artifactsDir docs/hydraia` (or skip it) for in-repo; the absolute external path
otherwise. Then create the external dir (with `specs/ plans/ qa/ runs/`) if chosen, and
use the resolved absolute base as **the artifacts base** for the whole run (see
*Artifacts base* below). If the user dismisses either question, default to in-repo + auto-commit
ON (behavior identical to prior versions). `/hydraia:resume` inherits both from the
run log if recorded, otherwise re-asks. The hooks read the same choice via
`hy_artifacts_dir` / `hy_repo_config` in `hooks/config.sh`, so the gate, agent caps,
plan-check, and summary all resolve to the same base — in-repo or external.

**Commit attribution (hard rule, every commit this pipeline makes).** Hydraia commits
carry a clean, conventional message and NOTHING else. NEVER add a `Co-Authored-By`
trailer for Claude, Hydraia, or any AI; never add a `🤖 Generated with…` line; never
add any AI-attribution footer. This overrides any default harness commit-trailer
behavior and applies everywhere a commit is made — executor per-task commits,
qa-automation, spec/plan commits, quick-mode, and any final commit. (The run-summary
credits line is separate and unaffected — it is printed to the user, not written into
git.)

**Artifacts base (path resolution).** Wherever this skill names a `docs/hydraia/<sub>`
path (specs, plans, qa, runs, `.active-plan`, `.quick-approved`, `.run-complete`,
`.heartbeats`, config), that path is
relative to the **resolved artifacts base** from the Storage gate — `docs/hydraia/` in
the repo by default, or the external dir when chosen. Resolve the base once at the
gate and use it for the rest of the run; when dispatching a task to a sub-agent, pass
the absolute base so the executor writes its heartbeat and any artifacts to the right
place. The shown `docs/hydraia/...` paths below are the default; substitute the
resolved base when the user chose external storage.

**Model guard.** Check the model this session is running on. If it is NOT Opus 4.8
(e.g. Sonnet 5), print this once, then continue anyway — never block:

> ⚠️ Hydraia runs best with the **main session on Opus 4.8**. Opus does the
> planning and both review passes, and is smart enough to delegate execution to
> Sonnet 5 sub-agents on its own — you don't switch models yourself. Consider
> restarting the session on Opus 4.8 for full quality. Continuing anyway.

**Two modes: design dialogue, then continuous execution.** The pipeline has a
conversational half and an autonomous half, split at the frozen plan.

- **Phases 1–3 (think → design → plan) are INTERACTIVE.** This is where design
  happens, so interaction is expected — not a violation. Run brainstorming as a real
  dialogue: ask clarifying questions (one at a time), propose 2–3 approaches with a
  recommendation, present the design, and get the user's approval before writing the
  spec. Do not compress this into a single question or skip it to "get to the code" —
  a design reached without dialogue is the exact failure this pipeline exists to
  prevent.
- **Phases 4–6 (execute → review → verify) are CONTINUOUS.** Once the plan is frozen,
  run every remaining phase to completion **without pausing**. Never insert "should I
  continue?" checkpoints between execution phases, never stop with the plan
  half-executed. The ONLY permitted stop here is a genuine BLOCKER a sub-agent cannot
  resolve — surface it, don't silently spin.

In short: **pause to get the design right; never pause once you're building it.**
(`/hydraia:plan` stops at the boundary — after Phase 3 — so you can review before the
autonomous half begins.)

**No proportionality escape (non-negotiable).** Token cost, change size, or "this
looks trivial / it's just a mirror of existing code" are NEVER reasons for YOU to
skip, compress, or inline a phase on your own. Whether a change is small enough to
skip the ceremony is the **human's** decision — never yours to make unilaterally. If
you are running the pipeline, run it in full: write the spec, write the plan,
delegate execution, run both review passes, run the real build/tests. A runtime gate
(`hooks/gate.sh`) enforces this — editing source code before Phase 3 freezes a plan
is blocked — so "compressing the ceremony" does not save effort, it just fails the
gate. The two sanctioned ways to skip are the human bypass and Quick-mode below.

**Quick-mode (human-gated shortcut, opt-in per change).** When a change is genuinely
trivial you MAY *offer* to skip the design ceremony — but the human decides, not you.

- **Eligibility (ALL must hold, else do NOT offer — run the full pipeline):** no new
  business logic; no new file; small, localized diff; a mirror of behavior that
  already exists and works; and it does **NOT** touch any security surface
  (authN/authZ, PII/financial data, untrusted/external input, secrets). If security
  surface is touched, Quick-mode is never eligible — the threat model is not
  skippable.
- **Ask, honestly.** Call `AskUserQuestion` once with a neutral pro/con:
  *"Found a simple, low-risk fix. Skip the spec/plan/double-review ceremony?"* —
  options `Run full pipeline` and `Quick-mode`. State plainly: **pro** — far fewer
  tokens, faster; **con** — no spec-drive record, no double review. Do not lead with
  the token savings or nudge toward skipping.
- **On `Run full pipeline` (or dismissal):** run Phases 0–6 normally. Default to this
  whenever unsure.
- **On `Quick-mode`:** write the approval marker with a one-line reason
  (`printf 'reason\n' > docs/hydraia/.quick-approved`), make the edit, then — always,
  non-negotiable — **run the project's real build/tests** and confirm they pass, and
  **commit with a clear message**. Remove the marker afterward
  (`rm -f docs/hydraia/.quick-approved`). Never write this marker without an explicit
  human "yes".



## NEXT

Read fully and follow `phases/phase-0-context.md`.
