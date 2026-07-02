# Hydraia

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Plugin version](https://img.shields.io/badge/plugin-v0.1.0-blue.svg)

A personal agentic development harness for Claude Code. One command runs the
entire feature pipeline — no per-step babysitting, no telling it which model or
skill to use each time.

```
/hydraia:feature add rate limiting to the public REST API
```

You stay on Opus 4.8; Hydraia decides everything else — when to brainstorm, when
to plan, when to drop to Sonnet for execution, which reviewers to run, which
security gates to enforce.

---

## Table of contents

- [What it does, automatically](#what-it-does-automatically)
- [Commands](#commands)
- [Worked examples](#worked-examples)
- [Use cases](#use-cases)
- [How it works under the hood](#how-it-works-under-the-hood)
- [Security (built in)](#security-built-in)
- [The one setup step](#the-one-setup-step)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [Repo layout](#repo-layout)
- [Notes](#notes)

---

## What it does, automatically

| Phase | What happens | Model |
|-------|--------------|-------|
| 0 · Context | Code graph synced (session hook) + queried; any PDF converted to markdown | Opus 4.8 |
| 1 · Think | Forced think-before-coding gate (karpathy-guidelines) | Opus 4.8 |
| 2 · Design | Brainstorm → exhaustive spec + threat model | Opus 4.8 |
| 3 · Plan | Detailed plan + self-review loop (max 2 passes) | Opus 4.8 |
| 4 · Execute | Fresh sub-agent per task; UI intelligence on frontend work | Sonnet 5 |
| 5 · Review | **Pass 1** whole-branch review + **Pass 2** ECC reviewers + security gate | Opus 4.8 |
| 6 · Verify | Run tests, confirm against spec, secrets/deps scan, summarize | Opus 4.8 |

Token discipline (compressed internal comms, `caveman` style) runs in the
background across all phases — it never touches code, plans, or your summary.

---

## Commands

| Command | Phases run | What it does |
|---------|-----------|--------------|
| `/hydraia:feature <desc>` | 0–6 | Full pipeline: context → think → design+threat-model → plan+self-review → execute (Sonnet 5) → double review + security gate (Opus 4.8) → verify + secrets/deps scan |
| `/hydraia:plan <desc>` | 0–3 | Context + design + threat model + detailed plan (with self-review), then **stop**. Nothing executed. |
| `/hydraia:review [focus]` | 5–6 | Double code review + security gate on the **current branch**. Code already exists. |
| `/hydraia:graph <query>` | — | Query the code graph (call sites, blast radius) without running the pipeline. |
| `/hydraia:doctor` | — | Validate, install, and update external deps (`codegraph`, `markitdown`), with consent. |
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

## Use cases

| Situation | Reach for |
|-----------|-----------|
| New feature, want it planned, built, reviewed, and verified in one shot | `/hydraia:feature` |
| Risky change — want to lock the design + threat model before committing effort | `/hydraia:plan`, then `/hydraia:feature` |
| Inherited a branch (yours or a teammate's) and want a rigorous, security-aware review | `/hydraia:review` |
| Estimating scope / deciding if a refactor is safe | `/hydraia:graph` |
| Security-sensitive code (auth, user input, external calls) where a design-level miss is expensive | any pipeline run — the threat model + 3 security gates are always on |
| Frontend work | `/hydraia:feature` — executors auto-consult `ui-ux-pro-max` for style, palette, type scale, a11y |

---

## How it works under the hood

Hydraia is a thin orchestration layer over bundled, battle-tested skills. It
holds no business logic of its own — it decides **what runs, in what order, on
which model.** Every skill and agent it uses ships inside the plugin (`skills/`,
`agents/`) — nothing external to install except two binaries (see Prerequisites).

**The skill is the contract.** `skills/hydraia/SKILL.md` defines the seven
non-negotiable phases. It forbids asking the user which model/skill/reviewer to
use, and forbids pausing between phases. This is what makes one command drive the
whole run.

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
| 1 Think | `karpathy-guidelines` |
| 2 Design | `brainstorming` |
| 3 Plan | `writing-plans` |
| 4 Execute | `subagent-driven-development`, `test-driven-development`, `ui-ux-pro-max` |
| 5 Review | `requesting-code-review`, `receiving-code-review`, ECC reviewer agents, `security-scan`, `security-review` |
| 6 Verify | `verification-before-completion`, `repo-scan`, `production-audit` |
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
| git | pipeline commits, `publish.sh` | No (prerequisite) |
| Node.js ≥18 + npm | installing `codegraph` | No (prerequisite) |
| Python 3.8+ + pip | installing `markitdown` | No (prerequisite) |
| `codegraph` | code-graph context | **Yes** |
| `markitdown` | PDF → markdown | **Yes** |
| `gh` CLI | only for `publish.sh` | No (optional) |

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

Then install the two external tools (validates and updates them too):
```
/hydraia:doctor
```

That's it — every skill and agent Hydraia uses ships inside the plugin, so there
is nothing else to clone or wire up.

---

## Repo layout

```
hydraia/
├── .claude-plugin/
│   ├── plugin.json               plugin manifest
│   └── marketplace.json          single-plugin marketplace (for `marketplace add`)
├── LICENSE                       MIT (Hydraia's own code)
├── NOTICE                        attribution for bundled skills/agents
├── LICENSES/                     upstream licenses (all MIT)
├── CONTRIBUTING.md               structure + how to add a bundled skill
├── README.md                     this file
├── publish.sh                    push a copy to your GitHub
├── skills/                       37 skills, all self-contained
│   ├── hydraia/                   the 7-phase pipeline contract (the brain)
│   ├── brainstorming/            requesting-code-review/   receiving-code-review/
│   ├── writing-plans/            executing-plans/          subagent-driven-development/
│   ├── dispatching-parallel-agents/                        using-git-worktrees/
│   ├── finishing-a-development-branch/  test-driven-development/  systematic-debugging/
│   ├── verification-before-completion/  using-superpowers/       writing-skills/
│   ├── karpathy-guidelines/      coding-standards/         caveman/
│   ├── react-patterns/          golang-patterns/          springboot-patterns/
│   ├── python-patterns/         microservices-architect/
│   ├── security-scan/           security-review/          security-bounty-hunter/
│   ├── repo-scan/               production-audit/         django-security/
│   ├── springboot-security/
│   ├── ui-ux-pro-max/           ui-styling/               design/
│   ├── design-system/           brand/                    banner-design/
│   └── slides/
├── agents/                       18 agents, all self-contained
│   ├── hydraia-executor.md       per-task executor (Sonnet 5)
│   ├── hydraia-reviewer.md       whole-branch reviewer (Opus 4.8)
│   ├── architect.md             code-architect.md         (architecture advisors)
│   ├── code-reviewer.md         security-reviewer.md      silent-failure-hunter.md
│   ├── go-reviewer.md           angular-reviewer.md       react-reviewer.md
│   ├── vue-reviewer.md          typescript-reviewer.md    python-reviewer.md
│   ├── java-reviewer.md         csharp-reviewer.md        database-reviewer.md
│   └── performance-optimizer.md type-design-analyzer.md
├── commands/                     feature, plan, review, graph, doctor, resume
├── hooks/
│   ├── hooks.json                registers preflight on SessionStart
│   ├── preflight.sh              codegraph sync + daily dep nudge
│   └── doctor.sh                 validate / install / update deps
└── docs/hydraia/                 plans/ and runs/ written by the pipeline
```

---

## Maintainer / forking

`publish.sh` is a maintainer helper — it is **not** part of installing Hydraia.
It pushes a copy of this repo to a GitHub account of your own (handy if you fork
Hydraia and want to host your own marketplace). Run it locally with `gh`
authenticated:

```bash
bash publish.sh                 # private repo named "hydraia"
bash publish.sh my-name public  # public repo, custom name
```

---

## Notes

Every skill and agent lives under `skills/` and `agents/` — nothing is fetched at
runtime. Some are Hydraia's own and some come from MIT-licensed upstreams; the
per-project license text is in `LICENSES/` and the attribution mapping in
`NOTICE`, as MIT requires. All of them are invoked internally by the pipeline —
you only ever call `hydraia`.
