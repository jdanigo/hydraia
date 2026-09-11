## Phase 3 — Plan + self-review loop (the "todo bien hechesito" gate)

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
     - `Files:` — `Create: exact/path`, `Modify: exact/path:line-range`,
       `Test: exact/path`. Exact paths, never "the relevant file".
     - `Interfaces:` — Consumes (signatures it uses from earlier tasks) and Produces
       (exact function names, parameter and return types later tasks rely on).
     - **Bite-sized TDD steps** (2–5 min each): write failing test → run it, expect
       fail → minimal implementation → run, expect pass → commit. With the exact
       test command and expected result per step.
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

   **Literal content, never a description of it.** A task that creates a file MUST
   embed the file's FULL verbatim content in a code block — never "create the file
   with the appropriate content". A task that edits a file MUST give the exact
   `old_string` → `new_string` (or a unique quoted anchor + the exact text to
   insert) — never "add error handling here". The executor copies; it does not
   compose.

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
2. **Self-review the plan (always TWO passes):**
   - Pass A: critique your own plan hard. **The Haiku test — apply it to every
     task:** could a model with zero context and no permission to make decisions
     produce EXACTLY the intended result from this task block alone? If any step
     needs the executor to infer, deduce, or invent, the task is under-specified —
     reject and push the decision up into the plan. Concretely, **reject and revise
     if ANY task:**
     - lacks exact `Files:` paths, `Interfaces:`, or independently testable steps,
       or says vaguely "edit the code / update the component";
     - **describes content instead of embedding it** — a create-file task without the
       full verbatim file, or an edit task without the exact `old_string`→`new_string`
       / quoted anchor + literal insert;
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
   - Pass B: run a **second full pass regardless** — even if Pass A found nothing,
     re-audit the whole plan against the same checklist with fresh eyes (Pass A can
     miss on the first read, and its own revisions introduce new gaps). Revise again
     if it finds anything.
   - Both passes always run. Stop after the two even if minor nits remain — do not
     loop forever.
3. The plan is frozen only after the self-review loop converges AND every task has
   file-level detail AND — when `qaFunctional` is on — the QA case doc exists and is
   committed AND (when ACs exist) every AC maps to at least one QA case and one plan
   task. If it does not, it is not frozen.
4. **Open a run log.** Create `docs/hydraia/runs/YYYY-MM-DD-HHMM-<feature>.md` with
   the original request, the plan path, and a phase checklist
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
   self-contained it BLOCKS the arm — so a plan that would fail on a cheap executor
   cannot reach Phase 4. If it blocks, inline the referenced content and re-arm.**
6. **Run-controls picker (LAST interactive step — the human sets the depth before the
   autonomous half runs).** The autonomous half (Phases 4–6) must not pause, so ask
   here, once, via a single `AskUserQuestion` with these two questions:

   **(a) Review depth** — how much of the Phase 5/6 ceremony to run on this change:
   - **Full** — double review, all matched language reviewers, security gates, QA,
     E2E, docs sync. (Default; pick when unsure.)
   - **Lite** — a single review pass, skip the non-core language reviewers and the
     docs-sync step; QA and the E2E gate still run per the repo's surface.
   - **Custom** — then a second `AskUserQuestion` (multiSelect) over the OPTIONAL
     stages only: `2nd review pass`, `language/framework reviewers`,
     `type-design / performance reviewers`, `docs sync`, `extra OWASP pass`.

   **Security floor (never offered as removable):** regardless of profile,
   `security-scan`, `code-reviewer`, `silent-failure-hunter`, `security-reviewer`, and
   one `hydraia-reviewer` pass ALWAYS run. The picker cannot switch these off — only
   the human's explicit `securityGates=false` config can, which is a separate act.

   **(b) Closing summary depth** — `Brief` (compact box) or `Detailed` (adds what
   shipped, per-agent-type counts, main-vs-sub token split, per-model in/out/cache).

   Record both answers in the run log and honor them in Phases 5–6. On dismissal,
   default to **Full** + **Brief**. This is the only question in the autonomous half's
   run-up — after it, Phases 4–6 run to completion without pausing.



## NEXT

Read fully and follow `phases/phase-4-execute.md`.
