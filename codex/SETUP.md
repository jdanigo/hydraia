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

A `PreToolUse` hook blocks `apply_patch` and write `shell` commands until a plan is
frozen — the same spec-drive discipline as the Claude plugin. Approval markers (any
one opens the gate): `.gate-approved`, `docs/hydraia/.quick-approved`,
`.hydraia/plan-frozen`. Escape hatch: `HYDRAIA_ALLOW_DIRECT=1`.

## Uninstall

```bash
rm -f ~/.codex/hooks.json
rm -rf ~/.codex/hooks ~/.codex/agents
rm -rf ~/.agents/skills/hydraia
```

Then remove the `# --- hydraia (added by codex/setup.sh) ---` block from
`~/.codex/config.toml` by hand (it is appended, not overwritten, so the rest of your
config is untouched).
