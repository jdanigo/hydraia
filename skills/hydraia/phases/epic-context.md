## Epic-context distiller (Agile Mode reference)

Produces `<base>/epics/<epic-slug>/epic-context.md` — the single distilled context each
story loads at orchestration time **instead of** the raw `epic.md` and planning docs. This
is the token-economy lever that makes running N stories affordable: a story executor reads
one 800–1500-token file, not the whole epic design. (Ported from BMAD `compile-epic-context`.)

### Task

Given the epic (`epic.md`), the story list (`stories.yaml`), and any planning artifacts,
compile a clean, developer-ready context file for the whole epic.

### Output format

```markdown
# Epic Context: {Epic Title}

<!-- Distilled from epic.md + planning artifacts. Regenerate if they change. -->

## Goal
{One paragraph: what the epic achieves and why.}

## Stories
- {id}: brief title only        # orientation, not detail

## Requirements & Constraints
{Functional/non-functional requirements and success criteria for the epic, by purpose.}

## Technical Decisions
{Architecture decisions, patterns, data models, conventions relevant across stories.}

## Threat-model constraints
{The epic threat model's load-bearing mitigations that every story must honor.}

## UX & interaction patterns
{Only if the epic has UI — the visual system + interaction constraints. Omit otherwise.}

## Cross-story dependencies
{Dependencies between stories or with external systems. Omit if none.}
```

### Rules

- **Scope aggressively** — only what a developer on any story actually needs; when in
  doubt, leave it out.
- **Describe by purpose, not by source** — "API responses must include pagination
  metadata", not "per epic.md §3.2".
- **No full copies** — distill; never paste large blocks.
- **Nothing derivable from the codebase** — don't restate what code already shows.
- **Target 800–1500 tokens total.** Above that, tighten — it loads into every story run.
- **Never invent** — if the source doesn't say it, don't add it.
- **Cache + invalidate.** Reuse an existing `epic-context.md` unless `epic.md` or a
  planning doc is newer (mtime); regenerate when stale.

This file is reference, loaded on demand by `phase-2a-decompose.md` and the orchestrator —
it is not a sequential step and has no `## NEXT`.
