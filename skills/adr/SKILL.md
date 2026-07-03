---
name: adr
description: Use when a design decision is made that is expensive to reverse, affects multiple components, or rejects a plausible alternative — record it as an Architecture Decision Record under docs/hydraia/adr/. Also use to supersede an old decision. Not for trivial choices.
---

# ADR — Architecture Decision Records (MADR-lite)

One file per decision: `docs/hydraia/adr/NNNN-<slug>.md`, zero-padded, monotonic (`0001-...`, `0002-...`). Find the next number with `ls docs/hydraia/adr/ | sort | tail -1`.

## When to write one (all it takes is ONE of these)

- Expensive to reverse (data store, auth model, hosting, framework).
- Affects multiple components or teams.
- A plausible alternative was seriously considered and rejected.

When NONE hold → no ADR. ADR spam buries the decisions that matter.

## Template

    # NNNN — <decision title>

    **Status:** proposed | accepted | superseded by NNNN
    **Date:** YYYY-MM-DD

    ## Context
    <the forces: requirements, constraints, and any assumption made because
    the human could not answer — stated as an assumption with its revisit
    trigger>

    ## Decision
    <what was decided, in one or two sentences, active voice>

    ## Alternatives considered
    - <alternative> — rejected because <reason>

    ## Consequences
    - Good: <what this buys>
    - Bad: <what this costs — every decision costs something; empty is a smell>

## Lifecycle rules

- Write at decision time (Phase 2 / greenfield step 5), commit with the spec.
- Supersede, never rewrite: a change of mind = NEW ADR + flip the old one's Status to `superseded by NNNN`. History stays honest.
- The Phase 2 spec references ADRs by number; reviewers check code against accepted ADRs.
