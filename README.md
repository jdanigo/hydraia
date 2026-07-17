# Hydraia

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Plugin version](https://img.shields.io/badge/plugin-v0.12.1-blue.svg)

🇬🇧 English · 🇪🇸 [Español](README.es.md)

A personal agentic development harness for Claude Code. One command runs the
entire feature pipeline: it **collaborates with you on the design** (brainstorm,
approaches, spec), then **builds autonomously** — plan, execute, double-review, and
verify with no per-step babysitting and no telling it which model or skill to use.

```
/hydraia:feature add rate limiting to the public REST API
```

You stay on Opus 4.8; Hydraia decides everything else — when to brainstorm, when
to plan, when to drop to Sonnet for execution, which reviewers to run, which
security gates to enforce.

---

## Visual overview

How one command drives the whole pipeline — the 7 phases (interactive design →
frozen plan → autonomous build), the Opus/Sonnet model split, and which phases
each main command runs.

![How Hydraia works: the 7-phase pipeline split into an interactive design half and an autonomous build half, with the frozen-plan gate between them, model badges per phase, and a table mapping each main command to the phases it runs.](docs/diagrams/hydraia-pipeline-en.svg)

---

## Table of contents

- [Why Hydraia](#why-hydraia)
- [What it does, automatically](#what-it-does-automatically)
- [Standout capabilities](#standout-capabilities)
- [Commands](#commands)
- [Worked examples](#worked-examples)
- [Plan once, execute anywhere](#plan-once-execute-anywhere)
- [Use cases](#use-cases)
- [Getting the most out of Hydraia](#getting-the-most-out-of-hydraia)
- [How it works under the hood](#how-it-works-under-the-hood)
- [Security (built in)](#security-built-in)
- [Spec-drive, enforced](#spec-drive-enforced)
- [The one setup step](#the-one-setup-step)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [Repo layout](#repo-layout)
- [Notes](#notes)

---

## Why Hydraia

Raw Claude Code is powerful, but hands-on. **You** decide when to plan, when to
threat-model, which reviewer to run, when to drop to a cheaper model — and you
carry all of it in one context window that bloats as the task grows. Skip a step
under time pressure and quality quietly drifts.

Hydraia removes the babysitting. **One command runs a fixed, non-negotiable
pipeline** — think → design + threat model → plan → execute → double review →
verify — with every model, skill, and reviewer decision already made. You stay on
Opus 4.8 and read one line per phase.

The point isn't "an agent that codes." It's the **discipline you'd apply on your
best day, applied on every run** — the threat model you'd skip when rushed, the
plan you'd hand-wave, the second reviewer you'd never bother to call, the tests
you meant to write. Hydraia doesn't let you skip them.

> **Without Hydraia:** pick a model, remember to plan, remember to threat-model,
> write it, remember to review, remember to run security, remember to test — every
> step manual, every step skippable.
>
> **With Hydraia:** `/hydraia:feature add rate limiting to the public API` — and
> all of it runs, in order, unattended.

---

## What it does, automatically

| Phase | What happens | Model |
|-------|--------------|-------|
| -1 · Triage | Intent detected and routed: feature · user story (PO) · bug · perf/DB · greenfield · review; ambiguous asks, never assumes | Opus 4.8 |
| 0 · Context | Code graph synced (session hook) + queried; any PDF converted to markdown | Opus 4.8 |
| 1 · Think | Forced think-before-coding gate (karpathy-guidelines) | Opus 4.8 |
| 2 · Design | Brainstorm → exhaustive spec + threat model | Opus 4.8 |
| 3 · Plan | Detailed plan + self-review loop (max 2 passes) | Opus 4.8 |
| 4 · Execute | Fresh sub-agent per task; heartbeat watchdog auto re-pushes hung agents; UI intelligence on frontend work | Sonnet 5 |
| 5 · Review | Depth chosen at plan freeze (Full/Lite/Custom, security floor always on) — **Pass 1** whole-branch + **Pass 2** diff-scoped reviewers + security gate, deduped | Opus (+ Sonnet/Haiku for mechanical) |
| 6 · Verify | Run tests, confirm against spec, secrets/deps scan, brief-or-detailed summary | Opus 4.8 |

Token discipline (compressed internal comms, `caveman` style) runs in the
background across all phases — it never touches code, plans, or your summary.

---

## Standout capabilities

The pipeline table above is *what* runs. These are the things that make the
output different from asking Claude Code to "build a feature" yourself — most of
them are steps you'd never run by hand on a normal day.

| Capability | Why it matters |
|-----------|----------------|
| **Code-graph context, not blind reads** | Every run starts by querying a `codegraph` index — structure, call sites, blast radius — instead of dumping files into context. Cheaper, more accurate, and it knows what a change will break *before* touching it. Query it directly with `/hydraia:graph`. |
| **Adversarial design loop** | Before the spec freezes, Hydraia red-teams its **own** design: unstated assumptions, a simpler approach it ignored, failure modes, security holes the threat model missed. Catching a design flaw here is ~10× cheaper than at review time. |
| **Security at three gates, not one** | Threat model at **design** time (before code exists) → cross-stack scan + OWASP review at **code** time → secrets/deps/production audit at **close**. Any high-severity finding blocks the run. |
| **Self-reviewing plans** | The plan critiques itself (up to 2 passes) for gaps, hidden coupling, missing tests, and over-broad changes — before a single line is written. |
| **Cost-aware model split** | Opus 4.8 does the judgment work (design, plan, both reviews); mechanical execution is delegated to Sonnet 5 sub-agents. You pay for Opus only where thinking actually matters. |
| **Fresh sub-agent per task** | Each executor gets only its task + graph context — never your session history. No context poisoning, no drift across a long run. |
| **Double code review** | A whole-branch reviewer pass, then a panel: 8 stack-specific reviewers (Go, Angular, React, Vue, TS, Python, Java, C#) plus cross-cutting ones (security, silent-failure, performance, types, database). |
| **Resumable runs** | Every run writes a durable log with a phase checklist. If it's interrupted — crash, closed laptop, killed session — `/hydraia:resume` picks it up exactly where it stopped. |
| **Persistent artifacts** | Specs and plans are saved under `docs/hydraia/` — reviewable, diff-able, reusable, and auditable after the fact. |
| **You pick the depth** | At plan freeze Hydraia asks how much review ceremony this change warrants (Full / Lite / Custom) and whether you want a brief or detailed closing summary — so a trivial fix need not pay for a full double review. The security floor is never skippable. |
| **Hung-agent watchdog** | Executors emit heartbeats; if one stalls without committing, the pipeline re-dispatches it automatically instead of waiting for you to nudge it — and surfaces a real blocker only after retries are exhausted. |
| **QA as a committed artifact** | Functional QA is written to `docs/hydraia/qa/` and committed — a reviewable Given/When/Then case matrix you can read and keep, not QA done in the model's head. |
| **Sub-agent-aware telemetry** | The local dashboard attributes tokens and models to each sub-agent (not just the main session), with per-model input/output and a per-run main-vs-sub split. |
| **Feed it a PDF** | Point it at a Jira export or a design-doc PDF; `markitdown` converts it to markdown before it enters context. No copy-paste. |
| **Plain-language trigger** | "add a `--dry-run` flag to the CLI…" auto-runs the whole pipeline — no slash command required. |
| **Bilingual** | Replies in English or Español (asked once per run). Code, commits, specs, and plans stay English and portable. |

---

## Commands

| Command | Phases run | What it does |
|---------|-----------|--------------|
| `/hydraia:feature <desc>` | 0–6 | Full pipeline: context → think → design+threat-model → plan+self-review → execute (Sonnet 5) → double review + security gate (Opus 4.8) → verify + secrets/deps scan |
| `/hydraia:plan <desc>` | 0–3 | Context + design + threat model + detailed plan (with self-review), then **stop**. Nothing executed. |
| `/hydraia:story <story>` | -1–3 | Product-Owner analysis of a user story (INVEST, ambiguity questions, numbered acceptance criteria) → spec → QA cases + traceability matrix → frozen plan, then **stop**. Nothing executed. |
| `/hydraia:perf <symptom>` | -1–6 | Measurement-first performance run: baseline → profile-driven diagnosis (`perf-engineer`) → spec with numeric target → implement → **re-measure** in verify. |
| `/hydraia:db <symptom>` | -1–6 | DB bottleneck run: engine detection, read-only evidence (EXPLAIN, stats, locks), findings by taxonomy, expand-contract migrations — `db-performance-tuner` as primary. |
| `/hydraia:architect <idea>` | -1–6 | Greenfield: guided elicitation → architecture proposals → confirmed stack → API contract → ADRs → full build pipeline. |
| `/hydraia:e2e [focus]` | — | Generate + run a Playwright critical-flow E2E suite (auto-detected framework). |
| `/hydraia:devops <request>` | — | Author CI/CD, Docker, or IaC — deploy and secrets flagged for human approval. |
| `/hydraia:observability <request>` | — | Instrument logs/metrics/traces/alerts — OTel-first, never logs secrets/PII. |
| `/hydraia:docs [focus]` | — | Sync README, API docs, CHANGELOG, ADR index with the code — reports drift. |
| `/hydraia:review [focus]` | 5–6 | Double code review + security gate on the **current branch**. Code already exists. |
| `/hydraia:graph <query>` | — | Query the code graph (call sites, blast radius) without running the pipeline. |
| `/hydraia:doctor` | — | Validate, install, and update external deps (`codegraph`, `markitdown`), with consent. **Run it inside the Claude Code CLI** (see [Install](#install)) — it is not a shell command. |
| `/hydraia:dashboard [port]` | — | Launch a local (127.0.0.1) web dashboard: plugin status, usage telemetry, and editable run modes. Zero-dependency Node server; all data stays on your machine. |
| `/hydraia:resume [run]` | resumes | Continue an interrupted pipeline from the last incomplete phase. |

The `hydraia` skill also **auto-triggers** when you ask to build/add/implement a
feature in plain language — no slash command required. `/hydraia:feature` is the
explicit, unambiguous entry point.

---

## Worked examples

### 1. Ship a full feature end to end

```
/hydraia:feature add rate limiting to the public REST API — 100 req/min
per API key, returning 429 with a Retry-After header
```

What you'll see, roughly one line per phase:

```
Running the Hydraia pipeline.
[0] Graph synced. Queried API middleware chain + route registration.
[1] Goal restated, assumptions listed, simplest approach chosen
    (token bucket per key, shared store).
[2] Spec written. Threat model: bypass via missing/rotated keys,
    memory exhaustion from unbounded key space, clock skew across nodes.
    Mitigations folded into spec.
[3] Plan saved: docs/hydraia/plans/2026-07-02-api-rate-limiting.md
    Self-review pass A found a missing test for the 429 header → revised.
[4] Executor #1: token-bucket store. Executor #2: middleware + headers.
    Executor #3: tests. All committed.
[5] Pass 1 (branch review) + Pass 2 (typescript-reviewer, security-reviewer,
    silent-failure-hunter) + security-scan/security-review. 1 material
    finding fixed.
[6] Tests green. Spec + mitigations confirmed. repo-scan/production-audit
    clean. Done.
```

### 2. Plan only — review the approach before any code is written

Use when you want to sanity-check the design and the file-by-file plan first.

```
/hydraia:plan migrate the session cache from in-memory to Redis with
a 30s TTL, keeping the current interface
```

Stops after Phase 3 with a frozen plan under `docs/hydraia/plans/`. Nothing is
executed. Run `/hydraia:feature` (or hand the plan to executors) when you're happy.

### 3. Review an existing branch you didn't build with Hydraia

```
/hydraia:review the auth module
```

Runs only Phases 5–6 on the current branch: both review passes, the cross-stack
security gate, and the pre-close secrets/deps scan. Findings ranked by severity;
high-severity security findings are treated as blockers. The optional focus
(`the auth module`) narrows attention.

### 4. Understand blast radius before touching anything

```
/hydraia:graph what calls parseConfig and what would break if I change
its return type
```

Pure code-graph query — call sites, dependents, blast radius. No pipeline, no
edits. Handy before deciding whether a change is surgical or sprawling.

### 5. No slash command at all

```
add a --dry-run flag to the CLI that prints planned changes without
writing them
```

The `hydraia` skill recognizes "add … feature" phrasing and runs the same full
pipeline. `/hydraia:feature` just removes the ambiguity.

---

## Plan once, execute anywhere

The plan that Phase 3 writes is deliberately **agent-agnostic**: every file to
touch, the change per file, the tests, and how to verify — written for an
implementer with *zero* prior context. That makes it a **portable hand-off
artifact**, not just an internal note. Which unlocks a cost- and speed-optimized
way of working: spend the expensive model only on judgment, and push the
token-heavy bulk anywhere you like.

**1 · Plan on Opus (judgment).**

```
/hydraia:plan add rate limiting to the public REST API — 100 req/min per
API key, 429 with Retry-After
```

Stops after Phase 3 with a frozen plan at
`docs/hydraia/plans/2026-07-02-api-rate-limiting.md` — independent, numbered tasks,
each self-contained.

**2 · Execute the tasks with whatever is cheapest / fastest.** The plan's tasks
are independent by design, so fan them out. Each executor needs only its task
block plus the repo — never the planning context.

| Executor | How you run it | Good for |
|----------|----------------|----------|
| Hydraia's own Sonnet sub-agents | run `/hydraia:feature <same request>` — it plans and executes with Sonnet sub-agents automatically | fully hands-off, single session |
| **Codex CLI** | hand a task block from the plan file to `codex` in another terminal | parallel execution, a different model's strengths |
| **Gemini** | paste a task block into Gemini | a third model / free-tier capacity |
| A second **Claude** session (Sonnet) | open another session, give it task 2 while session 1 runs task 1 | true parallelism across independent tasks |

**3 · Review on Opus (judgment again).**

```
/hydraia:review
```

Runs Phases 5–6 on the branch — double review + cross-stack security gate + verify
— **regardless of who wrote the code.** Codex wrote task 3? A Gemini session wrote
task 5? Doesn't matter; the review and security bar are identical.

**Why this wins:**

- **Token cost.** Opus — the expensive model — only touches the two phases where
  judgment actually pays off: planning and review. The token-heavy middle
  (execution) runs on cheaper models, other tools, or free tiers.
- **Parallelism.** Independent plan tasks run *at the same time* across
  agents/terminals instead of one-at-a-time inside a single context.
- **No context bloat.** Every executor starts clean with just its task, so none of
  them degrade the way one long-running session does.
- **Model diversity, one quality bar.** Different executors catch different things;
  the Opus review gate normalizes the result no matter the source.

You don't have to leave Claude to benefit — `/hydraia:feature` already does the
**Opus-plan → Sonnet-execute → Opus-review** split internally. Going multi-agent
simply extends that same principle across tools and terminals.

---

## Use cases

| Situation | Reach for |
|-----------|-----------|
| New feature, want it planned, built, reviewed, and verified in one shot | `/hydraia:feature` |
| A user story or ticket that needs PO-grade analysis before building — INVEST, acceptance criteria, QA cases traced to each AC | `/hydraia:story`, then `/hydraia:feature` |
| An endpoint or job got slow and you want it fixed with proof, not guesses | `/hydraia:perf` — baseline first, numeric target, re-measured in verify |
| Slow queries, lock timeouts, connection exhaustion, or an index question | `/hydraia:db` — EXPLAIN-first evidence, expand-contract migrations |
| A brand-new app or service, designed before the first line of code | `/hydraia:architect` — elicitation, architecture options, stack, API contract, ADRs |
| An API surface that should be designed before implementing | `api-design` runs inside greenfield/feature runs — contract-first OpenAPI/GraphQL/gRPC |
| Test coverage you can trace: every acceptance criterion → case → test file | on by default (`qaFunctional`) — the plan cannot freeze with an uncovered AC |
| Risky change — want to lock the design + threat model before committing effort | `/hydraia:plan`, then `/hydraia:feature` |
| Inherited a branch (yours or a teammate's) and want a rigorous, security-aware review | `/hydraia:review` |
| Estimating scope / deciding if a refactor is safe | `/hydraia:graph` |
| Security-sensitive code (auth, user input, external calls) where a design-level miss is expensive | any pipeline run — the threat model + 3 security gates are always on |
| Frontend work | `/hydraia:feature` — `ui-ux-pro-max` runs at design time to set style, palette, type scale, and a11y in the spec; executors implement that visual direction exactly |
| Turn a Jira ticket exported as PDF into shipped code | `/hydraia:feature path/to/ticket.pdf …` — it's converted to markdown before planning |
| Greenfield service/module from scratch | `/hydraia:architect` — `greenfield-architect` drives elicitation → architecture (`architect` + `code-architect`, `microservices-architect` for splits) → stack → `api-design` contract → ADRs before the spec |
| Big feature where token cost worries you | any pipeline run — the Opus/Sonnet split keeps the expensive model off the mechanical work automatically |
| Onboarding to a repo you've never seen | `/hydraia:graph` — map structure, call sites, and dependents without reading everything |
| Enforcing tests across a team's work | `/hydraia:feature` — TDD in Phase 4, spec-conformance + test run in the Phase 6 verify gate |
| A run got interrupted (crash, closed session) | `/hydraia:resume` — continues from the last incomplete phase |
| Pre-merge sign-off on someone else's PR branch | `/hydraia:review` — double review + cross-stack security gate, findings ranked by severity |
| A refactor that might sprawl across the codebase | `/hydraia:graph` first (blast radius), then `/hydraia:plan` to scope it before committing |

---

## Getting the most out of Hydraia

Small habits that meaningfully raise the quality of every run:

1. **Start the session on Opus 4.8.** The only lever you touch. Opus does the
   design and both reviews; it delegates execution to Sonnet on its own. On a
   weaker model the pipeline still runs, just with lower ceiling.
2. **Run `/hydraia:doctor` once.** It installs `codegraph` and `markitdown`. The
   graph context is where a large share of the value lives — without it, Phase 0
   falls back to blind reads.
3. **Write the request like a ticket, not a wish.** Goal + constraints +
   acceptance criteria. `add rate limiting — 100 req/min per API key, 429 with
   Retry-After` produces a far sharper spec and threat model than `add rate
   limiting`. The more concrete the input, the tighter every downstream phase.
4. **Use `/hydraia:plan` first on anything risky or expensive.** You approve the
   design and the file-by-file plan before spending a single execution token. Then
   run `/hydraia:feature` when you're happy.
5. **Point it at the PDF.** A Jira export or design doc — pass the path instead of
   copy-pasting. It gets converted and read in full.
6. **Check blast radius before you commit to a refactor.** `/hydraia:graph what
   calls X and what breaks if I change it` tells you surgical vs. sprawling in one
   query.
7. **Let it finish.** The pipeline is built to run unattended — the value is
   concentrated in exactly the phases (threat model, adversarial design pass,
   second review) you'd skip by hand.

---

## How it works under the hood

Hydraia is a thin orchestration layer over bundled, battle-tested skills. It
holds no business logic of its own — it decides **what runs, in what order, on
which model.** Every skill and agent it uses ships inside the plugin (`skills/`,
`agents/`) — nothing external to install except two binaries (see Prerequisites).

### The circuit, per command

Every run splits at the frozen plan: an **interactive half** where design happens
with you, and an **autonomous half** that builds without interruption.

```
/hydraia:feature <desc>          full pipeline
   Language gate · Model guard
  -1 Triage    intent → route: feature · story · bug · perf/DB ·
               greenfield · review (ambiguous → asks, never assumes)
   ┌─ INTERACTIVE (pauses allowed — this is where design happens) ─┐
   0 Context   codegraph query + PDF→md
   1 Think     karpathy gate · clarifying questions
   2 Design    brainstorm (questions → 2-3 approaches → present →
               YOUR approval) → write spec  docs/hydraia/specs/…
               + threat model + adversarial pass
   3 Plan      writing-plans (exact Files, Interfaces, TDD steps,
               literal content — the Haiku test) + qa-functional cases
               → self-review (rejects thin plans) → freeze plan
               → ARM gate (.active-plan)   ← needs spec + plan
   └─ AUTONOMOUS (never pause; only a real blocker stops it) ───────┐
   4 Execute   fresh hydraia-executor (Sonnet) per task · qa-automation
   5 Review    branch review (Opus) + reviewer panel + security gate
   6 Verify    run REAL build/tests · QA matrix · E2E gate · docs sync
               · repo-scan/prod-audit → DISARM gate · print credits

/hydraia:plan <desc>     Phases 0→3 only, then STOP
   writes spec + frozen plan, does NOT arm the gate, writes no code.
   The human review point before building. Then run /hydraia:feature.

/hydraia:story <story>   Phases -1→3, PO-first, then STOP
   story-analysis (INVEST, ACs) → spec → QA cases → frozen plan.

/hydraia:perf | :db <symptom>   measurement-first tuning route
   baseline → perf-engineer / db-performance-tuner → numeric target
   → build → Phase 6 re-measures against it.

/hydraia:architect <idea>   greenfield route
   greenfield-architect: elicit → architecture → stack → api-design
   contract → ADRs → full build.

/hydraia:review [focus]  Phases 5→6 on the current branch
   double review + cross-stack security gate + verify — no matter who
   (or what agent) wrote the code. Touches no earlier phase.

/hydraia:e2e | :devops | :observability | :docs   opt-in specialists
   e2e-runner · devops-engineer · sre-observability · docs-engineer.

/hydraia:graph <query>   codegraph only — call sites, dependents, blast
   radius. No pipeline, no edits.

/hydraia:doctor          validate / install / update codegraph + markitdown
/hydraia:resume [run]    read run log → continue from the last incomplete phase
```

**The spec-drive gate** (`hooks/gate.sh`, any repo with a `docs/hydraia/`) sits
across all of it — a source-code edit is blocked unless a plan is frozen
(`.active-plan`), a quick edit was human-approved (`.quick-approved`), or you set
`HYDRAIA_ALLOW_DIRECT=1`. Markdown and pipeline artifacts are exempt.

**The skill is the contract.** `skills/hydraia/SKILL.md` defines the phases and the
two modes: it forbids asking the user which model/skill/reviewer to use, requires a
real design dialogue in Phases 1–3, and forbids pausing once execution starts
(Phases 4–6). This is what makes one command drive the whole run.

**Two subagents carry the load:**

- `hydraia-executor` (`model: sonnet`) — dispatched fresh **per task** in Phase 4.
  Gets only the task + graph context, never session history. Surgical changes,
  tests, commits. Consults `ui-ux-pro-max` for any UI. Cheaper model where the
  work is mechanical.
- `hydraia-reviewer` (`model: opus`) — Phase 5 pass 1. Reviews the **whole branch**
  against spec, correctness, hidden coupling, test adequacy, over-engineering.

**Model split, restated:** the main session stays on Opus 4.8 for all the
judgment-heavy work (think, design, plan, both review passes). Execution is
*delegated* to Sonnet 5 — the main session never changes its own model, it spawns
executor subagents whose model is pinned in their frontmatter.

**Bundled skills do the actual thinking** (`skills/`, all MIT, licenses in `LICENSES/`):

| Phase | Bundled skill(s) used |
|-------|------------------------|
| -1 Triage | routing table in `hydraia`; `story-analysis`, `performance-tuning`, `db-optimization`, `greenfield-architect`, `systematic-debugging` per route |
| 1 Think | `karpathy-guidelines` |
| 2 Design | `brainstorming`; `api-design`, `adr`, `microservices-architect` on greenfield |
| 3 Plan | `writing-plans` + `qa-functional` (Given/When/Then cases + traceability matrix) |
| 4 Execute | `subagent-driven-development`, `test-driven-development`, `ui-ux-pro-max`, stack patterns (`react`/`node`/`dotnet`/`python`/`go`/`springboot`), `qa-automation`, `e2e-testing` |
| 5 Review | `requesting-code-review`, `receiving-code-review`, ECC reviewer agents, `security-scan`, `security-review` |
| 6 Verify | `verification-before-completion`, `repo-scan`, `production-audit`; QA matrix + E2E gate (`e2e-runner`) + docs sync (`docs-engineer`) |
| all | `caveman` — compresses internal/subagent comms only |

**Context comes from the code graph, not blind reads.** `hooks/preflight.sh`
runs `codegraph sync` (or `index` on first run) so Phase 0 can query structure,
call sites, and blast radius cheaply. PDFs (specs, tickets) are converted with
`markitdown` before entering context — never raw bytes.

**Plan artifacts persist.** Every plan is written to
`docs/hydraia/plans/YYYY-MM-DD-<feature>.md` and frozen only after the self-review
loop converges (max 2 iterations).

---

## Security (built in)

Security is enforced at three points, not just at the end:

- **Design (Phase 2):** threat model over the code graph's blast radius — attack
  surface, PII/financial data, authN/authZ, OWASP categories — folded into the
  spec so mitigations become plan tasks, not afterthoughts.
- **Review (Phase 5):** cross-stack `security-scan` + `security-review` (OWASP,
  secrets, injection, vulnerable deps) covering Node, C#, React, and Angular; plus
  `springboot-security` / `django-security` when the stack matches. High-severity
  findings block the merge.
- **Close (Phase 6):** `repo-scan` + `production-audit` for hardcoded secrets,
  vulnerable dependencies, and production-readiness gaps.

---

## Spec-drive, enforced

"Never skip a phase" is not just a prompt Hydraia hopes the model obeys — it's a
**runtime gate**. A `PreToolUse` hook (`hooks/gate.sh`) blocks any source-code edit
until Phase 3 freezes a plan. Design-before-code stops being aspirational: the model
literally cannot write code before the spec and plan exist.

- **Scope.** Only enforced in repos that use Hydraia (those with a `docs/hydraia/`
  directory). Markdown and the pipeline's own artifacts (specs, plans, run logs) are
  exempt, so writing the plan is never blocked.
- **The decision to skip is yours, not the model's.** Token cost or "this looks
  trivial" is never a valid reason for the model to bypass the pipeline on its own.
  There are exactly two sanctioned ways to skip:

  1. **Hard bypass (you, up front).** Set an env var in your shell — un-forgeable by
     the model, since it can't change the process environment the hook runs in:

     ```bash
     export HYDRAIA_ALLOW_DIRECT=1   # allow direct edits; unset to re-arm the gate
     ```

  2. **Quick-mode (per change, human-approved).** On a genuinely trivial change (no
     new logic, no new file, no security surface), the model may *ask you* via a
     prompt — "skip the ceremony? pro: fewer tokens; con: no spec-drive record, no
     double review." Only if **you** approve does it proceed, and even then it still
     runs the real build/tests. The model can never approve its own shortcut.

This closes the most common failure mode of prompt-only pipelines: a model that
rationalizes its way past the process on a change it judges "small."

---

## The one setup step

Run the **main session on Opus 4.8** (planning + both reviews). Execution drops
to Sonnet 5 by itself via the executor subagents. That's the only lever you touch.

If the session isn't on Opus, Hydraia tells you once and continues anyway — but
quality is best on Opus.

---

## Prerequisites

Have these on your machine **before** installing. `git`, Node, and Python are not
auto-installed; `/hydraia:doctor` installs the last two tools for you.

| Requirement | Used for | Auto-installed by `/hydraia:doctor` |
|-------------|----------|-------------------------------------|
| Claude Code | host | — |
| git | pipeline commits | No (prerequisite) |
| Node.js ≥18 + npm | installing `codegraph` | No (prerequisite) |
| Python 3.8+ + pip | installing `markitdown` | No (prerequisite) |
| `codegraph` | code-graph context | **Yes** |
| `markitdown` | PDF → markdown | **Yes** |
| `gh` CLI | GitHub PRs from the pipeline | No (optional) |
| Playwright/Cypress browser binaries | E2E tests (`e2e-runner`) | **Yes, opt-in** (`/hydraia:doctor` → `--install-e2e`, only once the repo already picked a framework) |

Platform: macOS/Linux. On Windows, run inside WSL.

---

## Install

Add the marketplace straight from GitHub, then install the plugin:

```bash
claude plugin marketplace add jdanigo/hydraia
claude plugin install hydraia
```

`marketplace add` clones the repo; `plugin install` reads
`.claude-plugin/marketplace.json` from that clone. Updates pull the latest
`main` (`claude plugin marketplace update hydraia`).

> Both commands run **inside the Claude Code CLI** too — start `claude` in your
> terminal first, then run them at its prompt.

![Adding the Hydraia marketplace and installing the plugin inside the Claude Code CLI — claude plugin marketplace add jdanigo/hydraia, then claude plugin install hydraia.](docs/diagrams/hydraia-install-terminal.svg)

That's it — every skill and agent Hydraia uses ships inside the plugin, so there
is nothing else to clone or wire up.

**You don't need to install the external tools by hand.** The first time you run
`/hydraia:feature`, Phase 0 detects whether `codegraph` and `markitdown` are present
and offers to install them inline — one click, no commands to memorize. You can
still run `/hydraia:doctor` yourself anytime to check or update them, and it prints
per-OS (`brew` / `apt` / `dnf` / `winget`) copy-paste commands for the system
runtimes (`git`, Node, Python) a plugin can't install for you.

> **`/hydraia:doctor` is a slash command, not a terminal command.** It only runs
> *inside* the Claude Code CLI session — after you type `claude` in your terminal
> and land on its prompt. Running `hydraia:doctor` or `claude /hydraia:doctor`
> directly in bash/zsh will not work.
>
> ```bash
> $ claude            # 1. start Claude Code first
> > /hydraia:doctor    # 2. then run this, at the Claude prompt
> ```

![Running /hydraia:doctor inside the Claude Code CLI — start `claude` in your terminal, then run the slash command at its prompt, and it checks codegraph, markitdown, and git.](docs/diagrams/hydraia-doctor-terminal.svg)

---

## Repo layout

```
hydraia/
├── .claude-plugin/
│   ├── plugin.json               plugin manifest
│   └── marketplace.json          single-plugin marketplace (for `marketplace add`)
├── LICENSE                       MIT (Hydraia's own code)
├── NOTICE                        attribution for upstream skills/agents
├── LICENSES/                     upstream licenses (all MIT)
├── CONTRIBUTING.md               structure + how to add a skill
├── README.md                     this file
├── skills/                       46 skills, all self-contained
│   ├── hydraia/                  the 7-phase pipeline contract (the brain)
│   ├── process (15)              brainstorming, writing-plans, executing-plans,
│   │                            subagent-driven-development, dispatching-parallel-agents,
│   │                            requesting-code-review, receiving-code-review,
│   │                            test-driven-development, systematic-debugging,
│   │                            using-git-worktrees, finishing-a-development-branch,
│   │                            verification-before-completion, using-superpowers,
│   │                            writing-skills, story-analysis
│   ├── stack patterns (9)       react-patterns, golang-patterns, springboot-patterns,
│   │                            python-patterns, coding-standards, karpathy-guidelines,
│   │                            microservices-architect, node-patterns, dotnet-patterns
│   ├── performance (2)           performance-tuning, db-optimization
│   ├── architecture (3)          greenfield-architect, api-design, adr
│   ├── security (7)             security-scan, security-review, security-bounty-hunter,
│   │                            repo-scan, production-audit, django-security,
│   │                            springboot-security
│   ├── e2e (1)                   e2e-testing
│   ├── ui / ux (7)              ui-ux-pro-max, ui-styling, design, design-system,
│   │                            brand, banner-design, slides
│   └── token discipline (1)     caveman
├── agents/                       26 agents, all self-contained
│   ├── hydraia-executor.md       per-task executor (Sonnet 5)
│   ├── hydraia-reviewer.md       whole-branch reviewer (Opus 4.8)
│   ├── architecture (2)          architect, code-architect
│   ├── qa (2)                    qa-functional, qa-automation
│   ├── performance (2)           perf-engineer, db-performance-tuner
│   ├── delivery (4)              e2e-runner, docs-engineer, devops-engineer, sre-observability
│   ├── language reviewers (8)    go-reviewer, angular-reviewer, react-reviewer,
│   │                            vue-reviewer, typescript-reviewer, python-reviewer,
│   │                            java-reviewer, csharp-reviewer
│   └── cross-cutting (6)         code-reviewer, security-reviewer, silent-failure-hunter,
│                                database-reviewer, performance-optimizer,
│                                type-design-analyzer
├── commands/                     feature, plan, story, perf, db, architect, e2e, devops, observability, docs, review, graph, doctor, resume, dashboard
├── hooks/
│   ├── hooks.json                registers preflight (SessionStart) + gate/plancheck (PreToolUse)
│   ├── preflight.sh              codegraph sync + daily dep nudge
│   ├── gate.sh                   spec-drive gate: blocks code edits before a plan is frozen
│   ├── plancheck.sh              self-containment gate: blocks arming a plan that references the spec
│   └── doctor.sh                 validate / install / update deps
└── docs/hydraia/                 specs/, plans/, and runs/ written by the pipeline
```

### Skills reference

| Skill | What it does |
|-------|--------------|
| `hydraia` | The 7-phase pipeline contract — the brain that drives every run |
| **Process** | |
| `brainstorming` | Explore intent, requirements, and design before any build |
| `writing-plans` | Turn a spec into a step-by-step implementation plan |
| `executing-plans` | Run a written plan in a fresh session with review checkpoints |
| `subagent-driven-development` | Execute independent plan tasks via fresh subagents |
| `dispatching-parallel-agents` | Fan out 2+ independent tasks with no shared state |
| `requesting-code-review` | Request review when a feature is done or before a merge |
| `receiving-code-review` | Triage review feedback with rigor, not blind agreement |
| `test-driven-development` | Write tests before implementation code |
| `systematic-debugging` | Structured root-cause analysis before proposing fixes |
| `using-git-worktrees` | Set up an isolated workspace for feature work |
| `finishing-a-development-branch` | Decide merge / PR / cleanup when work is done |
| `verification-before-completion` | Run checks and confirm output before claiming done |
| `using-superpowers` | How to find and invoke the right skill |
| `writing-skills` | Create, edit, and verify skills |
| `story-analysis` | Product-Owner pass — INVEST, ambiguity hunt, numbered acceptance criteria |
| **Stack patterns** | |
| `react-patterns` | React 18/19 idioms — hooks, RSC boundaries, Suspense, a11y |
| `golang-patterns` | Idiomatic Go patterns and conventions |
| `springboot-patterns` | Spring Boot architecture, REST, data-access patterns |
| `python-patterns` | Pythonic idioms, PEP 8, type hints |
| `coding-standards` | Cross-project naming, readability, immutability rules |
| `karpathy-guidelines` | Guardrails against common LLM coding mistakes |
| `microservices-architect` | Distributed systems, monolith decomposition, DDD, sagas |
| `node-patterns` | Node/TS backend playbook — async discipline, config, errors, DI, testing |
| `dotnet-patterns` | C#/.NET playbook — DI lifetimes, async/cancellation, EF Core, ProblemDetails |
| **Performance** | |
| `performance-tuning` | Measurement-first perf methodology — baseline, numeric target, re-measure |
| `db-optimization` | DB playbook — EXPLAIN-first, index design, N+1, expand-contract migrations |
| **Architecture** | |
| `greenfield-architect` | From-scratch design — elicitation, architecture, stack, contract, ADRs |
| `api-design` | Contract-first APIs — OpenAPI 3.1 / GraphQL SDL / gRPC proto3 |
| `adr` | Architecture Decision Records under docs/hydraia/adr/ |
| **Testing / delivery** | |
| `e2e-testing` | Playwright critical-flow playbook — page objects, stable selectors, flaky quarantine |
| **Security** | |
| `security-scan` | Scan `.claude/` config for injection and misconfig risks |
| `security-review` | Security checklist for auth, input, secrets, APIs |
| `security-bounty-hunter` | Hunt exploitable, report-worthy vulnerabilities |
| `repo-scan` | Classify every file, detect embedded third-party libs |
| `production-audit` | Local production-readiness audit, no external service |
| `django-security` | Django auth, CSRF, injection, secure deployment |
| `springboot-security` | Spring Security authn/authz, headers, secrets |
| **UI / UX** | |
| `ui-ux-pro-max` | UI/UX intelligence — styles, palettes, fonts, a11y, charts |
| `ui-styling` | Accessible components with shadcn/ui + Tailwind |
| `design` | Full design suite — logo, CIP, slides, banners, icons |
| `design-system` | Design tokens (primitive→semantic→component) + specs |
| `brand` | Brand voice, visual identity, messaging frameworks |
| `banner-design` | Banners for social, ads, web heroes, and print |
| `slides` | Strategic HTML presentations with Chart.js |
| **Token discipline** | |
| `caveman` | Compression style for internal reasoning to save tokens |

### Agents reference

| Agent | What it does |
|-------|--------------|
| `hydraia-executor` | Runs one plan task — writes code, tests, commits (Sonnet 5) |
| `hydraia-reviewer` | Whole-branch reviewer, Phase 5 pass 1 (Opus) |
| **Architecture** | |
| `architect` | System design, scalability, technical decision-making |
| `code-architect` | Feature blueprint anchored to existing codebase patterns |
| **QA** | |
| `qa-functional` | Derives Given/When/Then cases + traceability matrix from the spec (Sonnet) |
| `qa-automation` | Implements QA cases in the repo's test framework; verifies matrix coverage (Sonnet) |
| **Performance** | |
| `perf-engineer` | Profile-driven diagnosis: baseline, ranked bottlenecks, hypotheses (Opus) |
| `db-performance-tuner` | Multi-engine DB tuning: EXPLAIN, indexes, N+1, locks, pooling (Opus) |
| **Delivery** | |
| `e2e-runner` | Playwright critical-flow E2E; Phase 6 gate (Sonnet) |
| `docs-engineer` | Syncs README/API/CHANGELOG/ADR with code; Phase 6, non-blocking (Sonnet) |
| `devops-engineer` | CI/CD, Docker, IaC; deploy flagged for human approval (Sonnet) |
| `sre-observability` | Logs/metrics/traces/alerts; OTel-first, redaction-strict (Sonnet) |
| **Language reviewers** | |
| `go-reviewer` | Go — idioms, concurrency, error handling, performance |
| `angular-reviewer` | Angular — change detection, RxJS, signals, templates |
| `react-reviewer` | React — hook correctness, render perf, RSC boundaries |
| `vue-reviewer` | Vue — Composition API, reactivity, template security |
| `typescript-reviewer` | TS/JS — type safety, async correctness, security |
| `python-reviewer` | Python — PEP 8, idioms, type hints, security |
| `java-reviewer` | Java — Spring Boot / Quarkus layered review |
| `csharp-reviewer` | C# — .NET conventions, async, nullable, security |
| **Cross-cutting reviewers** | |
| `code-reviewer` | General quality, security, and maintainability review |
| `security-reviewer` | OWASP Top 10 — secrets, injection, SSRF, unsafe crypto |
| `silent-failure-hunter` | Swallowed errors, bad fallbacks, missing propagation |
| `database-reviewer` | PostgreSQL query, schema, and performance review |
| `performance-optimizer` | Bottlenecks, memory leaks, bundle size, render perf |
| `type-design-analyzer` | Type encapsulation, invariants, and enforcement |

---

## Forking

Fork on GitHub, then point `marketplace add` at your fork:

```bash
claude plugin marketplace add <your-user>/hydraia
claude plugin install hydraia
```

Everything Hydraia uses ships in the repo, so your fork is self-contained — nothing
else to wire up.

---

## Notes

Every skill and agent lives under `skills/` and `agents/` — nothing is fetched at
runtime. Some are Hydraia's own and some come from MIT-licensed upstreams; the
per-project license text is in `LICENSES/` and the attribution mapping in
`NOTICE`, as MIT requires. All of them are invoked internally by the pipeline —
you only ever call `hydraia`.
