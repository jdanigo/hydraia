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

Then remove the `# --- hydraia (added by codex/setup.sh) ---` block from
`~/.codex/config.toml` by hand (it is appended, not overwritten, so the rest of your
config is untouched).
