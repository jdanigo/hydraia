## Phase 2 — Design + threat model (Superpowers, this session = Opus)

Use **brainstorming**, and run it as a **real interactive dialogue** (this is the
interactive half — see "Two modes"). Do the actual brainstorming flow: ask clarifying
questions one at a time (purpose, constraints, success criteria), propose 2–3
approaches with trade-offs and your recommendation, then present the design and get
the user's approval. Do NOT jump straight from the prompt to a spec or to code —
design without dialogue is the failure this phase exists to prevent.

This phase produces a **written design spec — a real file, not inline reasoning**.
Skipping the written spec, or collapsing design into the plan, is a violation of the
pipeline. Be precise, not exhaustive: explore alternatives only where a real design choice
exists, and anchor every decision to what the code graph showed in Phase 0.

**Scale to the level (Phase -1).** Level 1 never reaches this phase (it writes a one-file
spec-plan). **Level 2:** the dialogue asks only the real intent gaps (below) and proposes
2–3 approaches only when there is a genuine choice; the threat model is a short note
unless security surface appears (then re-level to 3); no adversarial pass. **Level 3:**
everything in this file, in full.

**Intent gaps vs. your choices.** An intent gap is something the request does not say,
the code cannot settle, and the user would notice in the result — ask it (one at a time)
or record it under `## Open Questions` with the options and what each means. A choice the
user would not notice is yours: decide it and record it. Investigate before asking (repo,
planning docs, history — send broad searches to a `sonnet` sub-agent that returns a short
summary, so this session's context stays small). **Never write an unresolved gap into the
spec as an assumption.** The spec cannot be frozen while an Open Question remains.

**Write the spec to a file (mandatory artifact).** Save the design spec to
`docs/hydraia/specs/YYYY-MM-DD-<topic>-design.md` and commit it. Phase 3 MUST NOT
start until this file exists. The spec MUST contain, at minimum:

- **Goal** — one or two sentences on what this builds and why.
- **Chosen approach + rejected alternatives** (when a real choice existed) — the approaches considered, their
  trade-offs, and why the chosen one won. Not just the winner.
- **Code-graph anchors** — the existing structure, call sites, and blast radius from
  Phase 0 that the design must respect (name the real symbols/files).
- **Global constraints** — version floors, naming/copy rules, platform limits, and
  any acceptance criteria, with exact values.
- **Threat model + mitigations** — see below; folded in so they become plan tasks.
- **Frozen intent block.** Wrap `## Intent` (problem + approach), `## Boundaries`
  (**Always:** invariants · **Never:** non-goals and forbidden approaches) and the
  `## I/O & Edge-Case Matrix` (scenario | input/state | expected | error handling) in
  `<frozen-after-approval reason="human-owned intent">…</frozen-after-approval>`. After
  approval only the human changes what is inside; a review finding whose fix would edit
  it routes to `intent_gap` (ask), never to a silent rewrite.
- **Code Map** — the verified `file:line` / symbols to reuse and what must NOT change
  (from the code graph, not from memory). This is what lets executors write code against
  the real repo instead of inventing APIs.
- **Verification** — the exact commands that prove the change (from the baseline run),
  and manual checks when no command applies.
- **Spec Change Log** and **Review Triage Log** — empty, append-only sections Phase 5
  fills (see Phase 5 triage).
- **Size.** Aim for ~900–1600 tokens of spec for a Level-2 change: above that,
  implementation agents start losing the thread. If it grows past that because it holds
  several independent goals, offer the split (or Agile) instead of one giant spec.
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

**Design adversarial loop (Level 3, before freezing the spec).** After the spec +
threat model are drafted, run ONE adversarial pass against them: take the opposing
view and try to break the design — unstated assumptions, simpler approach ignored,
scalability/failure modes, security holes the threat model missed, spec requirements
that contradict each other. Revise the spec to close every real gap the pass finds.
This is the design-time analogue of the Phase 5 double review: catching a design
flaw here is an order of magnitude cheaper than at review time. One pass only — do
not loop forever.

**Threat model (before planning; full at Level 3, a short note at Level 2 when no security
surface is touched):** using the code graph's blast
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



## NEXT

Read fully and follow `phases/phase-3-plan.md`.
