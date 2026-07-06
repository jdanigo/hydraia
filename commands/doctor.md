---
description: Validate, install, and update Hydraia's external dependencies (codegraph, markitdown, E2E browser binaries)
argument-hint: (no arguments)
---

Run Hydraia's dependency doctor.

1. Run `"${CLAUDE_PLUGIN_ROOT}/hooks/doctor.sh" --check` and show me the full output.
2. If any prerequisite is missing (node, npm, python3, pip, git), tell me exactly how to install it — do NOT attempt to install prerequisites yourself.
3. If `codegraph` or `markitdown` is "not installed" or outdated, ask me to confirm before installing. Only after I confirm, run `"${CLAUDE_PLUGIN_ROOT}/hooks/doctor.sh" --install --yes` and report the results.
4. If the check reports an E2E framework detected with browsers "not installed", ask me to confirm before installing (mention the one-time ~100-300MB download). Only after I confirm, run `"${CLAUDE_PLUGIN_ROOT}/hooks/doctor.sh" --install-e2e --yes` and report the results. Never do this if no E2E framework was detected — that's a plan-level decision, not this command's.
5. If everything is already installed and current, say so and stop — do not install anything.
