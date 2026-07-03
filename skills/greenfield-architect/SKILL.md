---
name: greenfield-architect
description: Use when the user wants a new app, service, or system designed from scratch — greenfield work with no existing code to anchor to. Interactive architect: elicits requirements one question at a time, drives architecture proposals, recommends a stack with rationale, designs the API contract, and records every decision as an ADR. Never assumes scale, stack, or constraints.
---

# Greenfield Architect — design the system before the first line

Runs in the MAIN session (interactive). The "app from scratch" route of the Hydraia pipeline: everything here happens BEFORE the normal Phase 2 spec, and feeds it.

<HARD-RULES>
- One question at a time (AskUserQuestion, multiple-choice preferred). Never a questionnaire wall.
- Never pick a stack silently: recommendation + rationale + explicit human confirmation.
- Default architecture is a well-structured monolith. Splitting into services requires EVIDENCE from elicitation (scale, team topology); splitting without it is over-engineering and must be named as such.
- Every load-bearing decision becomes an ADR (adr skill). No decision lives only in chat.
- "No sé" is a valid human answer: propose a safe default, state the assumption explicitly in the ADR's Context, and set a revisit trigger.
</HARD-RULES>

## Flow

1. **Elicit** (in this order, one question each, skip what the request already answers):
   - Problem + primary users — what pain, who feels it.
   - Scale honesty — expected users/data/requests as ranges (10? 10k? 10M?). Push back on fantasy numbers.
   - Constraints — team size and skills (weighs heavily on stack), budget, deploy target (cloud/on-prem/serverless), compliance (PII? payments? health?).
   - Non-functional requirements — latency targets, availability, security posture.
   - Integration landscape — what existing systems it must talk to.
2. **Architecture proposal.** Dispatch the `architect` agent (system shape, trade-offs) and `code-architect` agent (concrete file/interface blueprint). Apply the `microservices-architect` skill ONLY if elicitation produced evidence for a split. Present 2–3 shapes with trade-offs and one recommendation.
3. **Stack recommendation.** Anchored to elicited constraints — team skills first, ecosystem fit second, hype never. Confirm with the human. Name the Phase 4 pattern skill that will govern implementation (react-patterns / node-patterns / dotnet-patterns / golang-patterns / springboot-patterns / python-patterns).
4. **API surface.** If the system exposes an API, run the **api-design** skill now — the contract file becomes part of the spec.
5. **Record decisions.** Architecture shape, stack, data store, auth approach, hosting — each gets an ADR via the **adr** skill, committed with the spec.
6. **Hand off** to the normal pipeline: Phase 2 spec references the ADRs by number and embeds/links the contract; Phases 3–6 run unchanged.

## Anti-patterns to refuse

- Microservices for a 2-person team "to be ready for scale" → monolith + ADR with the split trigger.
- Choosing the stack the model likes over the stack the team knows.
- Designing for 10M users when elicitation said 500.
- Skipping the API contract because "we can document it later".
