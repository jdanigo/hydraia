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

**Continuous execution.** Once the pipeline starts, run every phase to completion
without pausing. The ONLY permitted stops are: (a) the single clarifying question
allowed in Phase 1, and (b) a genuine BLOCKER a sub-agent cannot resolve — surface
it, don't silently spin. Never insert "should I continue?" checkpoints between
phases and never stop with the plan half-executed.

## Model policy (already decided — do not surface to the user)

- **This main session must run on Opus 4.8.** It does all analysis, planning,
  and both review passes. If the session is not on Opus, tell the user once:
  "Hydraia's planning and review run best on Opus 4.8 — switch the session model
  to Opus for full quality," then continue regardless.
- **Execution runs on Sonnet 5**, via the executor subagents (their model is
  pinned in their agent definitions). You do not change your own model to execute;
  you delegate.

## Phase 0 — Context (always first)

1. The session-start hook already ran a codegraph pre-flight sync. Do not ask the
   user to sync anything.
2. Query the code graph to understand existing structure, call sites, and blast
   radius before proposing anything. Prefer graph queries over blind file reads to
   save tokens.
3. If the request references a PDF (spec, ticket export, design doc), convert it
   with markitdown first (`markitdown <file>`), and work from the markdown. Never
   dump raw PDF bytes into context.

## Phase 1 — Think before coding (mandatory gate)

Apply the **karpathy-guidelines** skill. Do not write any code yet. Force the
analysis: restate the goal in your own words, list assumptions, name the simplest
approach that could work, and identify what could go wrong. Surgical changes over
broad rewrites. If the goal is ambiguous in a way that blocks correct design, ask
ONE clarifying question — otherwise proceed.

## Phase 2 — Design + threat model (Superpowers, this session = Opus 4.8)

Use **brainstorming** then produce a spec. Be exhaustive. Explore alternatives and
trade-offs. Anchor every decision to what the code graph showed in Phase 0.

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

1. Use **writing-plans** to write the implementation plan. Assume the implementer
   has zero prior context: name every file to touch, the change per file, tests,
   and how to verify. Save to `docs/hydraia/plans/YYYY-MM-DD-<feature>.md`.
2. **Self-review the plan (loop, max 2 iterations):**
   - Pass A: critique your own plan hard — gaps, hidden coupling (check the graph),
     missing tests, unstated assumptions, over-broad changes. Revise.
   - Pass B: repeat once more only if Pass A found substantive issues.
   - Stop after 2 iterations even if minor nits remain. Do not loop forever.
3. The plan is frozen only after the self-review loop converges.
4. **Open a run log.** Create `docs/hydraia/runs/YYYY-MM-DD-HHMM-<feature>.md` with
   the original request, the plan path, and a phase checklist
   (`- [ ] Phase 0` … `- [ ] Phase 6`). Update it at each phase boundary — check
   the box as each phase completes — so an interrupted run leaves a durable trail
   of where it stopped. `/hydraia:resume` reads this file.

## Phase 4 — Execution (delegated → Sonnet 5)

Use **subagent-driven-development**. Dispatch a fresh `hydraia-executor` subagent
per task (these run on Sonnet 5). Give each exactly the context it needs from the
plan and the graph — never your session history. Execute all tasks continuously.
TDD where the plan calls for it. Commit frequently.

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

Use **verification-before-completion**: run the tests, confirm the feature meets
the spec from Phase 2 (including the threat-model mitigations), and summarize what
shipped.

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
final summary to the user — those stay clear and complete.
