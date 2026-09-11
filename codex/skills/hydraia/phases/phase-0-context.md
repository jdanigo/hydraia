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

**Binding constraints (read first).** If `docs/hydraia/constraints.md` (or the external
artifacts base's `constraints.md`) exists, read it and treat every rule as BINDING for
this run — it is the repo's own "we don't do it this way" ledger and overrides default
behavior (never the safety gates). The SessionStart hook already injected it as context;
reading it here guarantees the full file is honored even if that injection was truncated.

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



## NEXT

Read fully and follow `phases/phase-1-think.md`.
