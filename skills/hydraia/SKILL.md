---
name: hydraia
description: Use whenever the user asks to build, add, implement, or change a feature or functionality — or brings a user story or ticket to analyze, reports a bug or unexpected behavior, asks for a branch review, or wants a new app or service designed from scratch. Phase -1 triages the intent and routes it. Runs the complete non-negotiable development pipeline end to end — deep analysis and planning, sub-agent execution, and a double code-review loop — without asking the user which model, skill, or step to use. This is the default way features get built.
---

# Hydraia — Agentic Development Pipeline

This skill defines the ONLY approved way to build a feature. Run every phase, in
order, automatically. **Never ask the user which model, skill, or reviewer to
use — those decisions are already made here.** Never skip a phase. Never pause
for "should I continue?" between phases.

Announce once at the start: "Running the Hydraia pipeline." Then proceed silently
through the phases, narrating at most one short line per phase.

## Phase -1 — Intent triage (before everything)

Classify the request into exactly ONE route before any other guard runs.
Explicit commands skip classification and force their route
(`/hydraia:feature` → feature · `/hydraia:story` → user story ·
`/hydraia:plan` → feature, stopping after Phase 3 · `/hydraia:review` →
review · `/hydraia:perf` → performance · `/hydraia:db` → performance,
DB-shaped · `/hydraia:architect` → greenfield · `/hydraia:e2e` → E2E suite ·
`/hydraia:devops` → DevOps config · `/hydraia:observability` → instrumentation ·
`/hydraia:docs` → docs sync). Plain-language requests are classified by signals:

| Intent | Signals | Route |
|---|---|---|
| Feature / change | "add / build / implement / change X" | Phases 0–6 as written below |
| User story | "As a … I want … so that …", acceptance-criteria lists, ticket text or a Jira/PDF export | Run the **story-analysis** skill FIRST (interactive PO pass → story artifact with numbered ACs), then Phases 0–3 with that artifact as the primary design input; continue into 4–6 only when the entry point runs the full pipeline |
| Bug / unexpected behavior | "fails / broken / error / regression / used to work" | **systematic-debugging** skill first — root cause before any fix. Enter the pipeline only if the fix requires new design/behavior; a surgical fix proceeds under that skill's rules (the spec-drive gate still applies) |
| Performance / DB symptom | "slow / timeout / high CPU / memory climbing / query takes …" | Run the **performance-tuning** skill flow: measured baseline FIRST, dispatch `perf-engineer` (and `db-performance-tuner` when the symptom is DB-shaped, per **db-optimization**), spec carries baseline + numeric target, Phase 6 re-measures against it |
| New app / greenfield | "from scratch / new app / new service / greenfield" | Run the **greenfield-architect** skill: elicitation → architecture proposals (`architect` + `code-architect`, microservices only with evidence) → confirmed stack → **api-design** contract when an API exists → **adr** records per decision — then Phases 0–6 |
| Review / audit | "review / audit this branch / this PR" | Phases 5–6 only |
| Ambiguous | none of the above clearly | `AskUserQuestion` listing the plausible routes — never assume |

Triage is ONE classification step, not a conversation — at most a single
routing question, and only when genuinely ambiguous. Route chosen, proceed
to the start-of-run guards below.

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

## Model policy (already decided — do not surface to the user)

- **This main session must run on Opus 4.8.** It does all analysis, planning,
  and both review passes. If the session is not on Opus, tell the user once:
  "Hydraia's planning and review run best on Opus 4.8 — switch the session model
  to Opus for full quality," then continue regardless.
- **Execution runs on Sonnet 5**, via the executor subagents (their model is
  pinned in their agent definitions). You do not change your own model to execute;
  you delegate.

## Phase 0 — Context (always first)

**Honor the effective config.** Read `docs/hydraia/config.json` (per-repo) and
`~/.config/hydraia/config.json` (global) if present — the dashboard
(`/hydraia:dashboard`) writes these. Per-repo overrides global; an env var overrides
both. The hooks already enforce the deterministic toggles (agent caps, spec-drive
mode, telemetry, run summary, codegraph auto). YOU honor the prompt-level ones:
`autoInstallDeps` (false → skip the install offer below), `reviewMode`
(`single` → run only the Superpowers review pass in Phase 5, not both),
`selfReviewPasses` (Phase 3 plan self-review count), `qaFunctional` (false → skip
the qa-functional dispatch in Phase 3, drop the AC-coverage freeze check, and skip
qa-automation in Phases 4 and 6), `e2eGate` (false → skip the Phase 6 E2E gate),
`docsSync` (false → skip the Phase 6 docs-engineer sync), `securityGates` (false → the
human disabled threat model / security scans; note it, do not silently assume they
ran), `pdfConversion` (false → skip markitdown), `cavemanInternal`,
`heartbeatStaleSecs` (Phase 4 watchdog: seconds before a commit-less task is deemed
hung, default 300), `maxTaskRetries` (Phase 4 watchdog: auto re-push attempts before a
stall becomes a blocker, default 2). Defaults apply when a key is absent.

0. **Dependency check + one-click install (do this once, silently if all present).**
   The user should never have to run install commands by hand. Detect what is
   available: `command -v codegraph`, `command -v markitdown`, `command -v npm`,
   `command -v pip` (or `pip3`).
   - If **all present** → say nothing, continue.
   - If a **managed** binary is missing but its installer is present (codegraph needs
     `npm`, markitdown needs `pip`), offer to install it **inline, once**, via
     `AskUserQuestion` — e.g. "Hydraia works best with codegraph (fast graph queries)
     and markitdown (PDF→markdown). Install now?" with options *Install now* /
     *Skip this run*. On **Install**, run the bundled installer (single source of
     truth) — resolve its path from the session cache and run it:
     ```
     ROOT="$(cat "${HOME}/.cache/hydraia/plugin-root" 2>/dev/null)"
     [ -n "$ROOT" ] || ROOT="$(ls -d "${HOME}/.claude/plugins/cache/hydraia/hydraia/"*/ 2>/dev/null | sort -V | tail -1)"
     "$ROOT/hooks/doctor.sh" --install --yes
     ```
     The installer is non-interactive and never uses sudo (no hangs). Its **last
     line is machine-readable** — `RESULT codegraph=<state> markitdown=<state>` where
     state is `ok` (usable now), `installed` (present, ready in a NEW session after a
     PATH refresh), or `missing` (failed — the installer printed the exact recovery
     command above it). **Read that line and act on it:**
     - `ok` → use the tool this run.
     - `installed` → tell the user it is ready next session; treat as unavailable for
       THIS run (degrade to file reads / skip PDF conversion). Do NOT re-offer.
     - `missing` → surface the one recovery command the installer printed. Do NOT
       loop or retry the install.
     On **Skip**, continue and do not ask again this run.
   - If an **installer itself** is missing (`npm`/`pip` absent, or `node`/`python3`/
     `git`), these are system runtimes a plugin must not auto-install — run
     `"$ROOT/hooks/doctor.sh" --check` and show the user its per-OS install hints
     (`brew`/`apt`/`dnf`/`winget`), then continue degraded. Never block the pipeline
     on a missing dependency.
1. The session-start hook already bootstrapped the code graph — `codegraph init` the
   first time in a project (initialize + index, in the background), or `codegraph
   sync` on later sessions. Do not ask the user to sync anything.
2. If `codegraph` is available, query the code graph to understand existing
   structure, call sites, and blast radius before proposing anything — prefer graph
   queries over blind file reads to save tokens. If the graph is unavailable
   (codegraph not installed, or a first-run index still building), do NOT assume it
   or invent results: fall back to targeted, minimal file reads for exactly the code
   you need, and suggest `/hydraia:doctor` once so it is ready next time. codegraph
   is an accelerator, never a hard requirement — the pipeline runs without it.
3. If the request references a PDF (spec, ticket export, design doc), convert it
   with markitdown first (`markitdown <file>`), and work from the markdown. Never
   dump raw PDF bytes into context.

## Phase 1 — Think before coding (mandatory gate)

Apply the **karpathy-guidelines** skill. Do not write any code yet. Force the
analysis: restate the goal in your own words, list assumptions, name the simplest
approach that could work, and identify what could go wrong. Surgical changes over
broad rewrites. Ask clarifying questions if the goal is ambiguous — you are in the
interactive half of the pipeline (see "Two modes"), so a real back-and-forth here is
correct; the deeper design dialogue continues in Phase 2.

## Phase 2 — Design + threat model (Superpowers, this session = Opus 4.8)

Use **brainstorming**, and run it as a **real interactive dialogue** (this is the
interactive half — see "Two modes"). Do the actual brainstorming flow: ask clarifying
questions one at a time (purpose, constraints, success criteria), propose 2–3
approaches with trade-offs and your recommendation, then present the design and get
the user's approval. Do NOT jump straight from the prompt to a spec or to code —
design without dialogue is the failure this phase exists to prevent.

This phase produces a **written design spec — a real file, not inline reasoning**.
Skipping the written spec, or collapsing design into the plan, is a violation of the
pipeline. Be exhaustive; explore alternatives and trade-offs; anchor every decision to
what the code graph showed in Phase 0.

**Write the spec to a file (mandatory artifact).** Save the design spec to
`docs/hydraia/specs/YYYY-MM-DD-<topic>-design.md` and commit it. Phase 3 MUST NOT
start until this file exists. The spec MUST contain, at minimum:

- **Goal** — one or two sentences on what this builds and why.
- **Chosen approach + rejected alternatives** — the 2–3 approaches considered, their
  trade-offs, and why the chosen one won. Not just the winner.
- **Code-graph anchors** — the existing structure, call sites, and blast radius from
  Phase 0 that the design must respect (name the real symbols/files).
- **Global constraints** — version floors, naming/copy rules, platform limits, and
  any acceptance criteria, with exact values.
- **Threat model + mitigations** — see below; folded in so they become plan tasks.
- **UX / visual direction** (mandatory when the change creates or touches UI) — the
  chosen style, colour palette, type scale, spacing/layout system, key interaction
  states, and the accessibility floor, decided HERE via **ui-ux-pro-max** — not left
  to markup-writing time. See the frontend-design rule below.

**Design approval (interactive gate, mandatory).** Present the design to the user and
get their approval BEFORE writing the spec file — this is `brainstorming`'s HARD-GATE
and it is honored, not skipped. Only pausing to "get to the code faster" defeats the
pipeline. The written spec + the adversarial self-review below are *in addition to*
the human approval, not a replacement for it. (Note: this human gate lives entirely in
the interactive half; once the plan is frozen and Phase 4 begins, the pipeline runs
autonomously to the end.)

**Architecture advice (greenfield / from-scratch work).** When the request builds a
new system, service, or module from scratch — not a surgical change to existing
code — first dispatch the architecture agents to propose the shape before the spec:
`architect` (system design, scalability, trade-offs) and `code-architect`
(concrete file/interface/data-flow blueprint anchored to existing patterns). If the
work spans multiple services or a monolith split, also use **microservices-architect**
(bounded contexts, communication patterns, resilience). Fold the chosen architecture
+ its rejected alternatives (and why) into the spec. For a FULL greenfield run
(routed by Phase -1 or `/hydraia:architect`), the **greenfield-architect** skill
drives this entire step — elicitation, these same agents, the api-design contract,
and ADRs. Skip this for small changes to existing code — it is for genuinely new
construction.

**Design adversarial loop (mandatory, before freezing the spec).** After the spec +
threat model are drafted, run ONE adversarial pass against them: take the opposing
view and try to break the design — unstated assumptions, simpler approach ignored,
scalability/failure modes, security holes the threat model missed, spec requirements
that contradict each other. Revise the spec to close every real gap the pass finds.
This is the design-time analogue of the Phase 5 double review: catching a design
flaw here is an order of magnitude cheaper than at review time. One pass only — do
not loop forever.

**Threat model (mandatory, before planning):** using the code graph's blast
radius, enumerate the attack surface this change introduces or touches —
untrusted inputs, authN/authZ boundaries, PII/financial data handled, external
calls, and secrets. Note the OWASP categories at risk. Bake the mitigations into
the spec so they become plan tasks, not afterthoughts. Catching a design-level
security flaw here is far cheaper than at review time.

**Frontend design (HARD GATE when UI is in scope — a precondition for freezing the
spec, not a suggestion):** visual quality is decided at design time, not patched on at
markup-writing time — a landing or screen that reads "flat / generic" was already flat
in the spec. This is the ONLY point in the whole pipeline where **ui-ux-pro-max** runs:
the executor subagents in Phase 4 have no Skill tool and cannot invoke it, so if you do
not run it HERE, nothing downstream will — the front end ships generic. That is the
exact failure this gate exists to stop.

So when this change creates or touches any UI, you (the interactive main thread, which
DOES have the Skill tool) MUST invoke **ui-ux-pro-max** during design and record its
output in the spec's *UX / visual direction* section: the chosen style, palette, type
scale, spacing/layout system, key component and interaction states, and the WCAG
accessibility floor — concrete values, not adjectives (exact hex, named font pairing,
spacing scale). **Enforcement:** the spec MUST NOT be frozen and Phase 3 MUST NOT start
until this section exists and is filled from ui-ux-pro-max output. A spec that reaches
Phase 3 with an empty or hand-waved *UX / visual direction* section for in-scope UI is a
gate failure — stop and run the skill. Phase 3 inlines this section verbatim into every
UI task and Phase 4 implements it exactly. (Purely back-end / non-visual changes skip
this gate entirely.)

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

## Phase 4 — Execution (delegated → Sonnet 5)

Use **subagent-driven-development**. Dispatch a fresh `hydraia-executor` subagent
per task (these run on Sonnet 5). Give each exactly the context it needs from the
plan and the graph — never your session history. Execute all tasks continuously.
TDD where the plan calls for it. Commit frequently.

**Dispatch in bounded waves — never fan out the whole plan at once.** Each subagent
loads its own context, so N parallel agents multiply token cost by ~N. Send at most
`HYDRAIA_MAX_CONCURRENT` (default 6) executors at a time; as they finish, send the
next wave. A whole run is also capped at `HYDRAIA_MAX_AGENTS` (default 30) total
dispatches. These limits are enforced at runtime by the agent-budget hook
(`hooks/agents.sh`) — a `Task` call past the cap is BLOCKED, not throttled silently,
so respect the waves rather than firing 100 tasks and retrying blocked ones. If a
plan truly needs more than the ceiling, that is the human's call to raise
(`export HYDRAIA_MAX_AGENTS=…`), never a reason to loop on blocked dispatches. This
is also why Phase 3 plans use coarse, consolidated tasks — a plan of 100+ atomic
tasks is a planning smell, not a parallelism win.

**Verify each task actually landed before dispatching the next wave (do not trust the
report alone).** A subagent's summary is not proof — a task can report "done" or
"delegated" without having committed (this failure is real, not hypothetical). After
each wave, confirm the work exists in git before moving on: `git log --oneline -<n>`
shows the expected commits and `git status --porcelain` is clean (or shows only the
next wave's territory). If a claimed commit is missing, re-dispatch that one task —
never build the next wave on an unverified one. The check costs a few tokens; a
corrupted run caught at Phase 6 costs far more.

**Hung-agent watchdog — heartbeats + auto re-push (no manual nudging).** A real run
had executors stall silently and need a manual "keep going" message. Detect and
recover automatically at every wave boundary:
- Each executor writes a heartbeat on start and after each commit to
  `docs/hydraia/.heartbeats/<task-slug>` (its agent definition does this). The file's
  epoch mtime is the liveness signal; the directory is gitignored.
- When a wave returns, for every task in it, confirm progress: a **commit exists**
  (the git check above) OR its **heartbeat is fresh** (mtime within
  `heartbeatStaleSecs`, default 300). A task with neither is treated as **hung/failed**
  and is **automatically re-dispatched ("pushed")** — you do not wait for the human to
  poke it. Re-push the SAME task with the same context, up to `maxTaskRetries`
  (default 2). Log each retry in the run log.
- If a task exhausts its retries without a commit, that is a genuine BLOCKER: stop and
  surface it with the evidence (no commit, stale heartbeat, retry count) — never spin
  on it silently. Bounded waves (`HYDRAIA_MAX_CONCURRENT`) keep a stall from taking the
  whole plan down with it.

**Frontend rule (hard gate, not optional):** any task that creates or changes UI —
markup, components, styles, or templates — the executor implements the *UX / visual
direction* the task carries from the Phase 2 spec (style, palette, type scale, spacing,
interaction states) EXACTLY, then verifies the WCAG accessibility floor. This is not
conditional on the executor self-classifying the task as "UI enough" — if the task
touches anything a user sees, the gate applies. Writing markup first and styling later
is the failure this prevents. The executor does NOT invoke ui-ux-pro-max itself —
executor subagents have no Skill tool, so the visual system is decided ONCE at design
time (Phase 2, below) and inlined into every UI task; the spec is the executor's single
source of truth. A UI task that reaches Phase 4 with no visual direction is a plan
defect — the executor reports it BLOCKED rather than inventing a generic look.

**Stack best-practices rule:** before writing non-trivial code, the executor
consults the matching patterns/standards skill so idioms are right the first time —
**react-patterns** (React), **golang-patterns** (Go), **springboot-patterns**
(Spring Boot), **python-patterns** (Python), **node-patterns** (Node/TypeScript
backends), **dotnet-patterns** (C#/.NET), and **coding-standards** (cross-cutting
naming, structure, and clean-code conventions for any stack).

**QA automation rule:** plan tasks that implement QA cases are dispatched to the
`qa-automation` agent (mode: implement) instead of a generic executor. It detects
the repo's existing test framework from evidence (config files, existing tests) —
if none exists it reports BLOCKED, because choosing a framework is a plan-level
decision. It names every test with its case ID (e.g. `TC-1.1`) and fills the
matrix `Test ref` column with `path/to/test:line` per case, or
`manual — <reason>` for cases that cannot be automated.

## Phase 5 — Code review (depth per the run-controls picker)

**Honor the review depth the human chose in Phase 3 step 6.** **Full** runs both passes
below. **Lite** runs only Pass 1 (Superpowers) plus the security floor, skips the
non-core language reviewers and the OWASP `security-review` extra pass. **Custom** runs
Pass 1 + whatever optional stages the human checked. In every profile the **security
floor is mandatory** — `security-scan`, `code-reviewer`, `silent-failure-hunter`,
`security-reviewer`, and one `hydraia-reviewer` pass always run; the picker cannot
remove them. Default (no answer recorded) is Full.

For a Full run, run BOTH passes — do not stop after one.

**Scope the panel to the diff — do not dispatch every reviewer on every run.** First
read the actual changed surface (`git diff --name-only` against the branch point).
Dispatch only the reviewers whose file types are present in the diff — running six
Opus reviewers on a two-file TypeScript change is wasted money. This is the single
biggest per-run cost lever, so route deliberately:

- **Always** (any diff): `security-reviewer`, `silent-failure-hunter`, and
  `code-reviewer` — correctness and security are never file-type-gated.
- **Only when that language/framework is in the diff:** `typescript-reviewer`
  (`.ts/.js`), `react-reviewer` (`.tsx/.jsx`), `vue-reviewer` (`.vue`),
  `angular-reviewer` (Angular files), `python-reviewer` (`.py`),
  `go-reviewer` (`.go`), `java-reviewer` (`.java`), `csharp-reviewer` (`.cs`),
  `database-reviewer` (SQL/migrations), `type-design-analyzer` /
  `performance-optimizer` only when the diff's nature (new public types, hot paths)
  actually warrants them.

**Model tiers — buy Opus only where judgment pays.** Correctness- and
security-bearing reviewers (`hydraia-reviewer`, `security-reviewer`,
`silent-failure-hunter`, the matched language reviewer) run on **Opus 4.8**.
Mechanical passes (style/lint-level nits, doc-comment checks) run on **Sonnet** or
**Haiku** — never spend Opus on a formatting scan.

1. **Pass 1 — Superpowers review:** use **requesting-code-review** to dispatch the
   `hydraia-reviewer` subagent (Opus 4.8) against the whole branch.
2. **Pass 2 — ECC review:** dispatch the diff-scoped reviewer set above (Opus for the
   correctness/security-bearing ones per the tier rule).
3. **Security gate (mandatory, cross-stack — always runs regardless of diff scope):**
   run the ECC security skills over the diff — **security-scan** (secrets, injection,
   unsafe patterns, vulnerable deps) and **security-review** (OWASP Top 10 semantic
   pass). These are language-agnostic and cover Node, C#, React, and Angular even
   though those have no dedicated security skill. For Spring Boot add
   **springboot-security**; for Django add **django-security**. Treat any
   high-severity finding as a blocker.
4. **Dedup before you triage.** Pass 1, Pass 2, and the security skills overlap — the
   same issue often surfaces three times. Collapse findings by (file, line, root
   cause) into one entry BEFORE triage, so you spend triage tokens once per real
   problem, not once per report. Then use **receiving-code-review** to triage: fix
   everything correct-and-material; high-severity security findings are
   non-negotiable. Re-review only the changed surface if fixes were substantial (max
   one re-review cycle).

## Phase 6 — Verify & close

Use **verification-before-completion**: actually **run** the project's real build
and test commands (e.g. `ng build`, `npm test`, `go build ./...`, `pytest`) and
read their output. Reviewing logic "inline" or "checking the math by hand" is NOT
verification — if a build/test command exists, you must run it and report the real
result. Confirm the feature meets the spec from Phase 2 (including the threat-model
mitigations), and summarize what shipped. If a build or test fails, the run is not
done — fix and re-run.

**QA matrix check (when `qaFunctional` is on and a QA case doc exists):**
dispatch `qa-automation` (mode: verify) against the case doc. Every case must be
either automated — its `Test ref` points at a real test that ran green in the
build above — or explicitly `manual — <reason>`. Any `pending`, missing ref, or
red case means the run is NOT done: fix and re-verify before closing.

**E2E gate (when `e2eGate` is on AND the repo has an E2E surface):** dispatch
`e2e-runner` (mode: verify). It runs the critical-flow suite with the real e2e
command; every non-quarantined critical flow must pass green. A failing critical
flow means the run is NOT done — fix and re-verify. If the repo has no E2E surface,
the gate is skipped (note it in the run log); never fabricate a suite to satisfy it.

**Docs sync (when `docsSync` is on):** dispatch `docs-engineer` (mode: sync). It
updates any README / API docs / CHANGELOG / ADR-index that drifted from the branch's
changed surface and reports what changed. This step never blocks the run — stale
docs do not fail a build; the report tells you what was updated.

**Disarm the gate.** Once the run is verified and done, remove the active-plan
marker so a later unrelated edit is gated again: `rm -f docs/hydraia/.active-plan`.
On a genuine blocker that ends the run early, leave the marker so `/hydraia:resume`
can continue without re-arming.

**Emit the run summary.** As the final close step, drop the one-shot marker that tells
the Stop hook to print the transcript-derived run summary (agents dispatched, models
used, real token usage). **Write the summary depth the human chose in Phase 3 step 6
as the marker's content** — `printf 'detailed\n' > docs/hydraia/.run-complete` for a
detailed breakdown, or `printf 'brief\n' > docs/hydraia/.run-complete` for the compact
box (default). The hook (`hooks/summary.sh`) reads that first line to pick verbosity,
then reads the real numbers from the session transcript plus Claude Code's on-disk
sub-agent transcripts (`<project>/<sessionId>/subagents/agent-*.jsonl`, one per
dispatched sub-agent, with a `.meta.json` naming its `agentType`) — so sub-agent tokens
and models are counted, not just the main session. Do NOT hand-write token or agent
counts yourself; they would be guesses.

**Telemetry logs for EVERY Hydraia route, not just `feature`.** Dropping this marker is
the last action of every route that does real model work — `feature`, `review`,
`resume`, `plan`, `story`, `perf`, `db`, `architect`, and the direct-agent commands
(`e2e`, `devops`, `observability`, `docs`, `graph`). Routes that stop before Phase 6
(e.g. `plan`/`story` at Phase 3, or a one-shot `graph` query) STILL drop the marker at
their end so the run is recorded — use `brief` unless the human explicitly chose
detailed. The Stop hook records only the DELTA since the previous marker this session
(a per-session cursor prevents double-counting when several commands run back to back),
so emitting once per command is correct, never inflating. Only the pure utilities
`dashboard` and `doctor` skip it (no model work to record). The credits line below is
separate: it is printed only for `feature`, `review`, and `resume`.

**Pre-close security gate (mandatory):** run **repo-scan** and **production-audit**
to confirm no hardcoded secrets, no vulnerable dependencies, and no obvious
production-readiness gaps were introduced. Do not report done while a high-severity
item is open. Only then report done. As the very last line of the run summary,
print the credits exactly:

    — Harness By José Daniel Garcés Ospina | Spec Drive Design First —

(Shown on every completed `feature`, `review`, and `resume` run. Not shown for
`plan` or `graph`.)

## Token discipline (background, always on)

Internal reasoning and subagent instructions use the **caveman** compression style
to save tokens. This NEVER applies to code, commit messages, specs, plans, or the
final summary to the user — those stay clear and complete. It is purely a wording
style for internal comms; it is NOT a mandate to save tokens by skipping,
compressing, or inlining any phase. Phase completeness always wins over token
economy (see "No proportionality escape").
