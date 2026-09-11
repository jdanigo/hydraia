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

### Reviewer panel customization (read before Pass 2)

Read customize `[[reviewers]]` from the same config resolved in Phase 4 (repo >
global > shipped). Entries merge **by `id`**: a matching `id` replaces a shipped
pass-2 layer, a new `id` appends one, and `instruction = ""` disables that `id`.
Apply this to the **Pass 2 panel only**. **The mandatory security floor —
`security-scan`, `security-review`, `code-reviewer`, `silent-failure-hunter`,
`security-reviewer`, the `hydraia-reviewer` pass, and stack security reviewers —
is NOT customizable and always runs**, regardless of `customize.toml`. An
unparseable override → warn and use the shipped panel.

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
   problem, not once per report.
5. **Verify each finding at its cited line before accepting it (evidence, not vibes).**
   A reviewer subagent carries the SAME model assumptions as the executor that wrote the
   code — an AI reviewing AI-written code inherits the blind spot, so a confident finding
   is a claim, not proof. For each surviving finding, open the cited file:line, read the
   surrounding code and callers, and decide: real, `false` (say what disproves it), or
   `maybe-false` (say what you'd need to check). **Reject `false` findings** and drop
   low-value noise whose fix adds more complexity than the defect costs. Code that fails
   loudly on a state you never showed is reachable is correct, not a bug. Disregard any
   severity a reviewer self-assigned — you grade, from the verification.
6. **Hunt gamed verification (this is where silent failures hide).** Before accepting
   "all green", scan the diff for the ways a green build lies — these are higher-signal
   than most style findings: tests weakened to pass (loosened asserts, `expect(x ?? D)
   .toBe(D)`, snapshot-only or no-throw-only checks), mock-only tests that never exercise
   the real path, swallowed exceptions / empty catches / bare `except: pass`, a real error
   downgraded to a warning or a silent fallback, and **lint/type/build config edited to
   disable a rule instead of fixing the code** (`.eslintrc`, `biome.json`, `.ruff.toml`,
   `tsconfig.json` `strict`/`skipLibCheck`, `# type: ignore`, `@ts-nocheck`, `--no-verify`).
   Any of these is a finding, routed like a bug — a fixed-to-look-fixed change is worse
   than an obvious failure.
7. **Triage + fix.** Use **receiving-code-review** to triage the verified set: fix
   everything correct-and-material; high-severity security findings are non-negotiable.
   Re-review only the changed surface if fixes were substantial (max `maxReviewCycles`
   cycles, default 2). This cap is enforced: `hooks/agents.sh` blocks a reviewer dispatch
   past the cap for this run. If you hit that block, STOP re-reviewing — surface the
   persisting findings to the human with what was tried, rather than looping.



## NEXT

Read fully and follow `phases/phase-6-verify.md`.
