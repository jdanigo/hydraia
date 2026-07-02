# Contributing to Hydraia

## Structure

- `skills/hydraia/SKILL.md` — the pipeline contract (the brain).
- `skills/*` — bundled skills the pipeline invokes (self-contained). Each is an
  upstream project, license in `LICENSES/`, attribution in `NOTICE`.
- `agents/*` — sub-agents (`hydraia-*` are ours; the rest are bundled ECC reviewers).
- `commands/*` — slash-command entry points.
- `hooks/` — `preflight.sh` (SessionStart), `doctor.sh` (deps), `hooks.json` (wiring).

## Adding or updating a bundled skill/agent

1. Copy the upstream skill dir into `skills/<name>/` (or agent into `agents/<name>.md`).
2. Add its LICENSE to `LICENSES/` and a line to `NOTICE`.
3. Update discovery counts in `.github/workflows/ci.yml` and this repo's docs.
4. Run the checks below.

## Checks (run before opening a PR)

```bash
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  python3 -m json.tool "$f" > /dev/null && echo "OK $f"
done
bash -n hooks/preflight.sh hooks/doctor.sh && echo "OK bash syntax"
echo "skills: $(find skills -name SKILL.md | wc -l)  agents: $(ls agents/*.md | wc -l)"
```

## Conventions

- Bash hooks target macOS/Linux (Windows via WSL). No PowerShell in v1.
- Nothing installs global packages except `hooks/doctor.sh --install`.
