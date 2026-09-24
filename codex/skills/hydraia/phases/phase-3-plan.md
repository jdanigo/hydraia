## Phase 3 — Plan + self-review loop (the "todo bien hechesito" gate)

Level 1 skips this phase (its one-file spec-plan was written at Phase -1). Levels 2 and 3
run it as written; the only difference is the run-controls step at the end.

0. **Precondition:** the Phase 2 spec file must already exist. If it does not, go
   back and write it — do not plan without a spec. **UI gate:** if the change touches
   any UI, the spec's *UX / visual direction* section must already be filled from
   ui-ux-pro-max output (see the Phase 2 Frontend-design hard gate). If it is empty or
   hand-waved, stop and run ui-ux-pro-max now — do not plan UI tasks against a missing
   visual system, because Phase 4 executors cannot recover it (they have no Skill tool).
1. Use **writing-plans** to write the implementation plan, saved to
   `docs/hydraia/plans/YYYY-MM-DD-<feature>.md`. Follow the writing-plans structure
   in FULL — a thin plan is a failed plan. The plan MUST contain:
   - **A header:** Goal, Architecture (2–3 sentences), Tech Stack, the path of the
     Phase 2 spec it derives from, and a **Global Constraints** block (exact values
     copied from the spec).
   - **A File Structure map:** every file to be created or modified and its single
     responsibility, before the tasks.
   - **Right-sized tasks:** each task is a coherent, independently shippable unit of
     work — not one micro-edit. Consolidate trivially-related edits into one task.
     A plan with dozens upon dozens of atomic tasks will fan out into just as many
     sub-agents in Phase 4 and multiply token cost; the agent-budget cap
     (`HYDRAIA_MAX_AGENTS`, default 30) will hard-stop it. Aim well under that
     ceiling by design.
   - **Per-task blocks**, each with:
     - `**Files:**` — `Create: exact/path`, `Modify: exact/path`, `Test: exact/path`
       (a `dir/` prefix or a glob is allowed when the set is genuinely open). Exact
       paths, never "the relevant file". **This list is the task's scope boundary:** at
       run time the plan-scope gate blocks edits to anything not declared in some task's
       Files — so declare every file the task may legitimately touch, tests included.
     - `**Verify:**` — the exact command + expected result that proves the task done
       (e.g. `` `pnpm vitest run src/cart` → 12 passed ``). It is the executor's stop
       condition. `plancheck.sh` blocks arming a plan whose tasks lack Files or Verify.
     - `Interfaces:` — Consumes (signatures it uses from earlier tasks) and Produces
       (exact function names, parameter and return types later tasks rely on).
     - `Exec class:` — one of **mechanical** | **logic** | **ui** | **qa**. This is
       what makes per-task model routing possible in Phase 4 (§ the execution-routing
       picker). Classify honestly, erring UP when unsure:
       - **mechanical** — boilerplate, wiring, config, repetitive/CRUD edits, pure
         data files, straightforward glue. Fully-specified enough that a cheap model
         (Haiku / Codex luna / Gemini Flash) executes it in one shot. This is the
         only class a cheap model may take.
       - **logic** — non-trivial algorithms, tricky state, concurrency, parsing,
         money/auth/crypto/security-sensitive code, anything with a design decision
         still latent. Never route to Haiku.
       - **ui** — any task touching markup/components/styles/templates (the Frontend
         hard gate applies; the executor must honor the inlined visual direction).
       - **qa** — implements QA cases → dispatched to `qa-automation`, not a generic
         executor.
       A task that lands on `logic` only because it is under-specified is a planning
       smell — specify it further so it can drop to `mechanical`, or accept the cost.
     - **Steps** for TDD tasks: failing test → run (expect fail) → implementation →
       run (expect pass) → commit, with the exact test command. Keep them few and real —
       the narrowest test command that covers the task's files, never the whole suite.
   Assume the implementer has zero prior context and cannot see the spec or your
   session — everything they need is in their task block. **Write to the weakest
   plausible executor:** the plan must be detailed enough that a cheaper or weaker
   model (Sonnet 5, Haiku, or an external agent like Codex or Gemini) can implement
   each task correctly with no judgment calls left open — exact paths, exact
   signatures, exact test commands. If a task would require the executor to infer
   intent or make a design decision, it is under-specified — push that decision up
   into the plan. This is where token cost is won or lost: a fully-specified task
   executes in one shot on a cheap model; an under-specified one forces a re-dispatch
   or an Opus rescue, which is the expensive path the plan exists to avoid.

   **Task content by Exec class — literal for mechanical, a contract for logic/ui.**
   - **`mechanical`** tasks carry **literal content**: a created file's FULL verbatim
     body, an edit's exact `old_string` → `new_string` (or a unique quoted anchor + the
     exact text). The executor copies; it does not compose. This is what lets Haiku or
     an external cheap runtime run them in one shot.
   - **`logic` / `ui`** tasks carry a **contract**, not pre-written code: the intent (2–3
     lines), a **Code Map** (the verified `file:line` / symbols to reuse and what must
     not change — from the code graph, not memory), **Always / Never** boundaries, the
     I/O rows this task must satisfy, and **Verify**. The Sonnet executor writes the code
     against the real repo with the compiler and tests in the loop. Why: code written
     inside a plan never meets a compiler — that is where invented APIs and wrong
     signatures are born, and each one later costs a fix loop. Do not pre-write logic you
     have not compiled.
   Both shapes must be **self-contained** — the rules below apply to both.

   **Never point at the spec (or any other document/code) for content the executor
   must produce.** This is the single most common self-containment failure. A task
   that says "implement per spec §3", "follow the skeleton in the design",
   "match the existing User validation", or "see the spec for the schema" is NOT
   self-contained — the executor may be a context-less cheap model (Gemini Flash,
   Codex, Haiku) that CANNOT and WILL NOT open the spec, so it guesses, truncates,
   or invents. Inline the actual content into the task, even though it duplicates the
   spec. **Here DRY yields to self-containment:** the spec holds design rationale;
   the task holds everything needed to execute, repeated in full. This is exactly why
   the plan is a portable hand-off artifact ("execute anywhere" — Codex, Gemini, a
   second session): portability only holds if every task carries its own content. A
   runtime hook (`hooks/plancheck.sh`) scans the frozen plan's task bodies for these
   reference smells and BLOCKS the gate-arm if it finds any — so a referencing plan
   cannot reach execution.

   **State each task's execution environment — assume nothing from context.** A cheap
   executor does not know your repo's toolchain. Every task that runs anything gives
   the EXACT command (not "run the tests" but `pnpm vitest run src/x.test.ts`), the
   working directory, any dependency/env-var/service precondition, and — if it depends
   on an earlier task's output — names that task and the files it must find already
   present. Out-of-order or standalone execution must fail loudly, not silently guess.

   **Verify completeness of large literals, not just existence.** A cheap model can
   truncate a long verbatim block. For any sizable inlined file, the task's
   verification confirms it landed WHOLE — e.g. `wc -l file → N` or a grep for the
   exact last line — not merely that the file exists.

   **Anchor edits by unique quoted text, never by line number alone.** Line numbers
   drift as earlier tasks change the file; every `Modify` must carry a unique text
   anchor the executor can match exactly. State this in the task.

   **Every UI task carries its visual direction inline.** A task that creates or
   changes UI MUST embed the concrete decisions from the Phase 2 *UX / visual
   direction* section — the exact style, palette values, type scale, spacing,
   component/interaction states it must produce, and the WCAG accessibility floor to
   verify. The executor implements these values directly and does NOT invoke
   ui-ux-pro-max (it has no Skill tool); the inlined direction IS the visual system.
   Because Phase 4 runs autonomously on a weak executor, "make it look good" or
   "see the spec for styling" is NOT self-contained — the executor cannot open the
   spec and will fall back to generic defaults. Inline the values, per the
   self-containment rule above. A UI task with no visual direction in its body is
   under-specified and produces flat output.

   **Every task carries a runnable verification with its expected output** — not
   only TDD steps. Config, docs, and scaffolding tasks each end with an exact
   command and the exact output that proves the task landed (e.g.
   `grep -c X file → 2`). A task with no way to self-check is under-specified.

   **QA cases (parallel, when `qaFunctional` is on) — ALWAYS a committed document,
   NEVER inline.** Functional QA is produced as a reviewable artifact, not performed
   in your head. While writing the plan, dispatch the `qa-functional` agent (Sonnet)
   with: the spec path, the story artifact path if one exists, and the output path
   `docs/hydraia/qa/YYYY-MM-DD-<slug>-cases.md`. It returns Given/When/Then cases plus
   a traceability matrix (`AC → Cases → Test ref`, refs start as `pending`) and a GAPS
   section. **Non-negotiable rules:**
   - **You (the main agent) MUST NOT write the test cases inline or "apply QA
     yourself."** Dispatch `qa-functional`; the value is a durable document the human
     can read, review, and upload to the repo — not ephemeral reasoning.
   - **The document is always produced and committed.** Even when the run has no
     formal acceptance criteria, instruct `qa-functional` to derive implicit ACs from
     the spec's behavior so a case doc still results. After it returns, **commit the
     file** (`git add docs/hydraia/qa/<file> && git commit`) so it lands in the repo.
   - Surface every GAP to the human BEFORE freezing the plan — gaps are design
     questions, never things to guess around.
   - The plan must contain the test tasks that implement these cases (see the Phase 4
     QA automation rule). The frozen-plan condition below includes "the QA case doc
     exists and is committed."
2. **Self-review the plan (Pass A, plus Pass B only when needed):**
   - Pass A: critique your own plan hard. **The executor test, per task:** for a
     `mechanical` task — could a model with zero context and no permission to make
     decisions produce EXACTLY the intended result from this block alone? For a
     `logic`/`ui` task — could a capable engineer with the repo but no session
     context implement it from this contract without having to ask something the user
     would notice? If a task needs the executor to guess intent, it is under-specified —
     push that decision up into the plan. Concretely, **reject and revise
     if ANY task:**
     - lacks exact `Files:` paths, `Interfaces:`, or independently testable steps,
       or says vaguely "edit the code / update the component";
     - **a `mechanical` task describes content instead of embedding it** (full verbatim
       file / exact `old_string`→`new_string`), or **a `logic`/`ui` task lacks its contract**
       (intent, Code Map with verified `file:line`, Always/Never, Verify) — or pre-writes
       uncompiled logic instead of specifying it;
     - **references the spec, another document, or other code for content it must
       produce** — "follow spec §X", "see the design", "as in the spec", "match the
       existing X" — instead of inlining that content into the task (the
       `plancheck.sh` hook blocks the gate-arm on these, but catch them here first);
     - **runs a command without the exact invocation** ("run the tests" with no
       command/dir), or **assumes an earlier task's output without naming it**, or
       **lacks a completeness check on a large inlined literal** (existence only, no
       line-count / last-line assert);
     - **anchors an edit to a bare line number** instead of a unique quoted string;
     - **lacks a runnable verification with expected output** (not just TDD tasks —
       config/docs/scaffolding too);
     - **contains a placeholder** — `TODO`, `TBD`, `...`, "similar to Task N",
       "add appropriate X", "handle edge cases" — repeat the real content instead;
     - **references a name (symbol, file, agent, skill) that no earlier task defines
       and does not already exist**, or uses an inconsistent name/signature across
       tasks (`foo()` in Task 3 vs `fooBar()` in Task 7 is a bug).
     When `qaFunctional` is on, also reject if any acceptance criterion lacks BOTH a
     QA case (in the qa-functional doc) and an implementing task in the plan. Also
     hunt gaps, hidden coupling (check the graph), missing tests, unstated
     assumptions, over-broad changes, and drift from the spec. Revise.
   - Pass B: only if Pass A made a **material** revision (a task added, split, or its
     contract changed) — re-audit just the revised tasks and their neighbours, since
     revisions introduce new gaps. If Pass A changed nothing material, there is no
     Pass B.
   - At most two passes. Stop after them even if minor nits remain — do not loop.
3. The plan is frozen only after the self-review loop converges AND every task has
   file-level detail AND — when `qaFunctional` is on — the QA case doc exists and is
   committed AND (when ACs exist) every AC maps to at least one QA case and one plan
   task. If it does not, it is not frozen.
4. **Open a run log.** Create `docs/hydraia/runs/YYYY-MM-DD-HHMM-<feature>.md` with
   the original request, the plan path, the level, and a phase checklist
   (`- [ ] Phase 0` … `- [ ] Phase 6`). Update it at each phase boundary — check
   the box as each phase completes — so an interrupted run leaves a durable trail
   of where it stopped. `/hydraia:resume` reads this file.
5. **Arm the spec-drive gate.** Only after BOTH the Phase 2 spec file and the frozen
   plan exist (and NOT before), write the frozen plan's path into the marker file
   `docs/hydraia/.active-plan`
   (e.g. `printf '%s\n' "docs/hydraia/plans/<file>.md" > docs/hydraia/.active-plan`).
   The `gate.sh` hook blocks all source-code edits until this marker exists — which
   is exactly why no code can be written before Phases 2–3 complete. Do not arm the
   marker if the spec is missing. (`/hydraia:plan` stops here and does NOT arm the
   marker — planning must never authorize edits.) **A second hook
   (`plancheck.sh`) fires on this arm command and scans the plan's task bodies for
   reference smells ("follow spec §X", "see the design", etc.); if the plan is not
   self-contained, or a task lacks its contract (`**Files:**` + a Verify line), it
   BLOCKS the arm — so a plan that would fail on an executor cannot reach Phase 4. If it
   blocks, fix the named tasks and re-arm.**
6. **Run controls — computed, announced, asked only when it matters.** The autonomous
   half (Phases 4–6) must not pause, so settle its controls here. Compute each one,
   then **announce them in one line** — ask a question only in the Level-3 case below.
   Routes that reach Phase 3 (`feature`, `perf`, `db`, `architect`, `story`, `plan`) all
   do this; `review` runs only Phases 5–6 and honors `customize.toml` `[[reviewers]]`.

   **(a) Review depth — derived from the level, never asked.** Level 3 → **Full**
   (judge + diff-scoped language reviewers + security floor + QA + E2E per surface);
   Level 2 → **Lite** (judge + security floor + the language reviewer matching the diff);
   Level 1 → judge + `security-scan`. **Floor, never removable:** `hydraia-reviewer` +
   `security-scan` always; `security-reviewer` + `silent-failure-hunter` at Levels 2–3.
   Only the human's explicit `securityGates=false` config can switch them off, which is a
   separate act.

   **(b) Execution routing — computed.** Options (what each gets / costs vs Balanced):
   - **Balanced — Sonnet for every task.** Baseline ≈ 1×.
   - **Economy — Haiku for `mechanical`, Sonnet for `logic`/`ui`, `qa-automation` for
     `qa`.** ≈ 0.3–0.6× on mechanical-heavy plans; a borderline Haiku task is retried by
     the breaker, it does not stall.
   - **Max quality — Sonnet for `mechanical`, Opus for `logic`/`ui`.** ≈ 2–4×. The only
     routing under which executors may run on Opus.
   - **Hand-off — freeze the plan, do not execute here** (external cheap runtime later
     via `/hydraia:resume` or `$hydraia` in Codex).
   Recommendation: ≥ ~60% `mechanical` and no `gate.yaml` risk → **Economy**; the user
   asked for lowest cost / async, or the `plan` route → **Hand-off**; otherwise
   **Balanced**. Max quality is never auto-picked — it is the human's choice.
   **Record it for the runtime:** `mkdir -p <base>/.agents && printf '%s\n' <routing>
   > <base>/.agents/routing` (`balanced|economy|max-quality|handoff`). The Opus gate in
   `hooks/agents.sh` reads this file; without `max-quality` there, an executor dispatch
   on Opus is blocked.

   **(c) E2E strategy — computed.** No user-facing/service surface → **None**. UI with
   no real-service integration → **Playwright**. DB/queue/external-service integration
   → **Playwright + Testcontainers** (needs Docker; verified at the Phase-6 gate, BLOCKED
   with the recovery if absent — never a silent skip). Honor `customize.toml`
   `[e2e].strategy` when concrete.

   **(d) Closing summary** — `brief` unless the human asked for detail.

   **Announce** (Levels 1–2): one line, e.g. *"Run controls: Lite review · Economy
   (7/9 mechanical) · E2E none · brief summary."* The human can override by replying;
   otherwise continue.

   **Ask once (Level 3 only)** — a single `AskUserQuestion` with the computed values
   pre-selected: routing (Balanced / Economy / Max quality / Hand-off), E2E strategy,
   and **where to execute**: *Continue here* / *Continue in a fresh session* (the
   frozen plan + run log carry everything; `/hydraia:resume` picks up at Phase 4 with a
   clean context — recommended after a long design dialogue, because the orchestrator's
   context is what fills up, not the executors'). Honor `customize.toml`
   `[executor].routing` / `[e2e].strategy` when concrete (then skip those questions).

   **If Hand-off or fresh session:** finalize the plan, record the choices in the run
   log, and STOP after Phase 3 with the exact resume command. Hand-off does NOT arm
   `.active-plan` for local execution; a fresh-session continuation leaves it armed.

   Record every value in the run log (`level`, `review`, `routing`, `e2e`, `summary`) and
   honor them in Phases 4–6. On dismissal of the Level-3 question, use the computed
   values.

## NEXT

Read fully and follow `phases/phase-4-execute.md`.
