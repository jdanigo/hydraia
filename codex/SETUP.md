# Hydraia — Codex Setup

Installs the hydraia spec-drive pipeline layer for [OpenAI Codex CLI](https://github.com/openai/codex),
mirroring the Claude Code plugin's gate, model routing, and orchestrator skill —
without touching the shipped Claude surface.

## Prerequisites

- **Codex CLI ≥ 0.139**, with the `hooks` and `multi_agent` features enabled. Check with:

  ```bash
  codex features list
  ```

  Enable any that are off in your Codex config before installing.

- **Windows:** the hooks and installer are bash scripts, so native Windows needs
  **Git Bash or WSL** (a `bash` on PATH). With that, everything works as-is. A native
  PowerShell port is on the roadmap (see below).

## Install

Run the installer from the repo root. It writes everything **user-level**
(`~/.codex/…` and `~/.agents/skills/…`), never repo-local — repo-local hooks hit a
known Codex bug ([openai/codex#17532](https://github.com/openai/codex/issues/17532)).

```bash
bash codex/setup.sh
```

This is idempotent and non-destructive:

- `~/.codex/hooks.json` and `~/.codex/hooks/*.sh` — the gate + preflight + plancheck hooks.
- `~/.codex/agents/*.toml` — the executor and reviewer agent definitions.
- `~/.codex/config.toml` — merged with the hydraia model-routing block (appended once,
  never overwriting existing config).
- `~/.agents/skills/hydraia/SKILL.md` — the Codex-native orchestrator skill.

Pass `--home <dir>` to install into an alternate home directory (used by the test
suite; you should not normally need it).

## Invoke

Inside a Codex session, run:

```
$hydraia <what to build>
```

The orchestrator skill runs the full spec-drive pipeline: triage, analyze,
spec + threat model, plan + self-review, sub-agent execution, double review, verify.

## Model routing

- **Orchestrator / plan / spec / design / review** (this session) → `gpt-5.6-sol`
  (frontier tier — judgment-heavy work).
- **Executor sub-agents** (one per plan task) → `gpt-5.6-luna` (cheap tier — mechanical
  execution against a fully-specified task).
- **Reviewer sub-agents** (`hydraia-reviewer`, `code-reviewer`, `security-reviewer`) →
  `gpt-5.6-sol` (frontier tier — correctness and security review).

## Gate

A `PreToolUse` hook blocks `apply_patch` (the edit tool) until a plan is frozen — the
same spec-drive discipline as the Claude plugin. Approval markers (any one opens the
gate): `.gate-approved`, `docs/hydraia/.quick-approved`, `.hydraia/plan-frozen`. Escape
hatch: `HYDRAIA_ALLOW_DIRECT=1`. Verified live: interactive Codex fires the hook and
blocks `apply_patch`.

**Known limitation (shell escape).** Codex's built-in shell tool (`exec_command`) does
**not** run `PreToolUse` hooks — shell execution is governed by Codex's sandbox/approval
layer, not the hook layer. So a determined model can still write via a shell redirect
(`printf … > file`). The gate hook already contains the shell-write detection logic, and
`hooks.json` matches `exec_command`, but Codex never invokes the hook for it. Closing this
is a roadmap item (below): gate shell via a `PermissionRequest` hook, and/or run Codex
with `sandbox_mode = read-only` until the plan is frozen.

## Roadmap

- **Airtight shell gate:** intercept `exec_command` via a `PermissionRequest` hook and/or
  a sandbox-mode flip on plan freeze, since `PreToolUse` does not cover the shell tool.
- **Native Windows:** PowerShell (`gate.ps1` / `setup.ps1`) equivalents so Git Bash / WSL
  is not required, with PowerShell-aware write detection (`Out-File`, `Set-Content`, `>`).

## Uninstall

```bash
rm -f ~/.codex/hooks.json
rm -rf ~/.codex/hooks ~/.codex/agents
rm -rf ~/.agents/skills/hydraia
```

Then remove the `# --- hydraia root ---` and `# --- hydraia agents ---` blocks from
`~/.codex/config.toml` by hand (they are merged in, not overwritten, so the rest of your
config is untouched).

## Airtight write-gate (read-only sandbox)

`setup.sh` pins two keys in `~/.codex/config.toml`:

```toml
sandbox_mode = "read-only"
approval_policy = "on-request"
```

Under read-only, the OS sandbox blocks every filesystem write, so each write escalates
to Codex's approval path and fires the **`PermissionRequest`** hook (`gate.sh`). This is
what closes the shell bypass: `PreToolUse` never fires for Codex's `exec_command`, but
`PermissionRequest` does. The decision is deterministic and fail-closed:

- **Frozen-plan marker present** (`.gate-approved`, `docs/hydraia/.quick-approved`,
  `.hydraia/plan-frozen`, or `HYDRAIA_ALLOW_DIRECT=1`) → **allow** (autonomous half).
- **No marker, `apply_patch`** → **deny** (source edits blocked before a plan exists).
- **No marker, shell write** → **ask** (you approve in the interactive design half; this
  is also how the plan-marker bootstrap write is approved). Post-freeze it flips to allow.
- **Unparseable payload** (empty/garbled, or naming neither tool nor event) → **deny**,
  fail-closed. The gate blocks anything it cannot understand.

The sandbox is **never flipped to workspace-write** — the model cannot self-elevate.
Reads run free (they do not escalate).

**The marker is the trust anchor — create it yourself, not via the model.** The frozen-plan
marker is what opens the gate, so it must be created by a human (or `HYDRAIA_ALLOW_DIRECT=1`,
an env var the model cannot forge), never written by the model through the gated tools.
The `ask` on pre-freeze shell writes is **human-gated by construction**: Codex hooks fire
only in interactive TUI/desktop (not `codex exec`), so a human is always present to answer.

**`apply_patch` is hard-`deny` but shell writes are `ask`** — an asymmetry: a model could
prefer `printf > src/x` (→ ask) over `apply_patch` (→ deny) to attempt a pre-freeze source
write. `ask` still requires your approval, but if you want a symmetric hard block set
**`HYDRAIA_GATE_STRICT=1`** — pre-freeze shell writes then `deny` too (you then bootstrap
the plan-marker with `HYDRAIA_ALLOW_DIRECT=1` or by creating the marker file yourself).

**Codex UI desktop:** the desktop app uses the same core (`CODEX_CLI_PATH` → ChatGPT.app)
and reads the same `~/.codex/config.toml` + hooks, but routes approvals to its own UI and
uses the app-server, which can override the sandbox per turn. Verify the three gate checks
there too; if it differs, that difference is a known limitation, not a silent pass.

**Populated-config edge (security-critical):** the merge prepends root keys. If your
`~/.codex/config.toml` already sets a root `sandbox_mode`, `model`, or `approval_policy`,
a blind prepend would DUPLICATE those keys — invalid TOML, or (last-wins) a **silent
sandbox downgrade** back to `workspace-write` that defeats the gate. `setup.sh` detects
this and **refuses** to touch root keys (it installs only the agent tables and prints a
warning). In that case, set `sandbox_mode = "read-only"` and `approval_policy = "on-request"`
yourself, or move hydraia's root keys into a `[profiles.hydraia]` table and launch with
`codex --profile hydraia`. After install, confirm: `grep sandbox_mode ~/.codex/config.toml`
shows exactly one line, `= "read-only"`.

**Windows:** Git Bash or WSL for now (native PowerShell hooks are on the roadmap).
