---
name: hydraia
description: Use whenever the user asks to build, add, implement, or change a feature or functionality. Runs the complete non-negotiable development pipeline end to end — deep analysis and planning, sub-agent execution, and a double code-review loop — without asking the user which model, skill, or step to use. This is the default way features get built.
---

# Hydraia — Agentic Development Pipeline

This skill defines the ONLY approved way to build a feature. Run every phase, in
order, automatically. **Never ask the user which model, skill, or reviewer to
use — those decisions are already made here.** Never skip a phase. Never pause
for "should I continue?" between phases.

Announce once at the start: "Running the Hydraia pipeline." Then proceed silently
through the phases, narrating at most one short line per phase.

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
+ its rejected alternatives (and why) into the spec. Skip this for small changes to
existing code — it is for genuinely new construction.

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

## Phase 3 — Plan + self-review loop (the "todo bien hechesito" gate)

0. **Precondition:** the Phase 2 spec file must already exist. If it does not, go
   back and write it — do not plan without a spec.
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
   model (Sonnet 5, or an external agent like Codex or Gemini) can implement each
   task correctly with no judgment calls left open — exact paths, exact signatures,
   exact test commands. If a task would require the executor to infer intent or make
   a design decision, it is under-specified — push that decision up into the plan.
2. **Self-review the plan (always TWO passes):**
   - Pass A: critique your own plan hard. **Reject and revise if ANY task lacks
     exact `Files:` paths, `Interfaces:`, or independently testable steps**, or says
     vaguely "edit the code / update the component". Also hunt gaps, hidden coupling
     (check the graph), missing tests, unstated assumptions, over-broad changes, and
     drift from the spec. Revise.
   - Pass B: run a **second full pass regardless** — even if Pass A found nothing,
     re-audit the whole plan against the same checklist with fresh eyes (Pass A can
     miss on the first read, and its own revisions introduce new gaps). Revise again
     if it finds anything.
   - Both passes always run. Stop after the two even if minor nits remain — do not
     loop forever.
3. The plan is frozen only after the self-review loop converges AND every task has
   file-level detail. If it does not, it is not frozen.
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
   marker — planning must never authorize edits.)

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

**Frontend rule:** if a task creates or changes UI, the executor MUST consult the
**ui-ux-pro-max** skill for styles, palettes, typography, and accessibility before
writing markup.

**Stack best-practices rule:** before writing non-trivial code, the executor
consults the matching patterns/standards skill so idioms are right the first time —
**react-patterns** (React), **golang-patterns** (Go), **springboot-patterns**
(Spring Boot), **python-patterns** (Python), and **coding-standards** (cross-cutting
naming, structure, and clean-code conventions for any stack).

## Phase 5 — Double code review (both passes on Opus 4.8)

Run BOTH passes. Do not stop after one.

1. **Pass 1 — Superpowers review:** use **requesting-code-review** to dispatch the
   `hydraia-reviewer` subagent (Opus 4.8) against the whole branch.
2. **Pass 2 — ECC review:** dispatch the ECC reviewer agents (Opus 4.8):
   `code-reviewer`, `security-reviewer`, and `silent-failure-hunter` at minimum;
   add the language-specific reviewer that matches the stack —
   `csharp-reviewer` / `java-reviewer` for .NET & Spring Boot,
   `typescript-reviewer` for Node & TypeScript, `react-reviewer` for React,
   `angular-reviewer` for Angular, `vue-reviewer` for Vue,
   `python-reviewer` for Python, `go-reviewer` for Go.
3. **Security gate (mandatory, cross-stack):** run the ECC security skills over the
   diff — **security-scan** (secrets, injection, unsafe patterns, vulnerable deps)
   and **security-review** (OWASP Top 10 semantic pass). These are language-agnostic
   and cover Node, C#, React, and Angular even though those have no dedicated
   security skill. For Spring Boot add **springboot-security**; for Django add
   **django-security**. Treat any high-severity finding as a blocker.
4. Use **receiving-code-review** to triage findings from all passes. Fix everything
   that is correct-and-material; high-severity security findings are non-negotiable.
   Re-review only the changed surface if fixes were substantial (max one re-review
   cycle).

## Phase 6 — Verify & close

Use **verification-before-completion**: actually **run** the project's real build
and test commands (e.g. `ng build`, `npm test`, `go build ./...`, `pytest`) and
read their output. Reviewing logic "inline" or "checking the math by hand" is NOT
verification — if a build/test command exists, you must run it and report the real
result. Confirm the feature meets the spec from Phase 2 (including the threat-model
mitigations), and summarize what shipped. If a build or test fails, the run is not
done — fix and re-run.

**Disarm the gate.** Once the run is verified and done, remove the active-plan
marker so a later unrelated edit is gated again: `rm -f docs/hydraia/.active-plan`.
On a genuine blocker that ends the run early, leave the marker so `/hydraia:resume`
can continue without re-arming.

**Emit the run summary.** As the final close step, drop the one-shot marker that
tells the Stop hook to print the transcript-derived run summary (agents dispatched,
models used, real token usage): `printf 'done\n' > docs/hydraia/.run-complete`.
The hook (`hooks/summary.sh`) reads the numbers straight from the session
transcript and removes the marker after emitting — do NOT hand-write token or agent
counts yourself; they would be guesses. Skip this only for `plan`/`graph`, which do
not complete a build.

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
