---
description: Launch the local Hydraia dashboard (status, usage telemetry, editable config) in the browser
argument-hint: [port]
---

Start the Hydraia dashboard — a local, zero-dependency web server (Node built-ins
only) bound to `127.0.0.1` (never exposed to the network). It shows plugin status
(version, skills, agents, hooks, MCP servers, dependency health), local usage
telemetry (agents, models, tokens, skills — all recorded locally, never
transmitted), and lets you edit the run modes (agent caps, spec-drive, telemetry,
review rigor, and more).

1. Resolve the plugin root and the port (default from config, or `$ARGUMENTS` if
   given):
   ```
   ROOT="${CLAUDE_PLUGIN_ROOT:-$(cat "${HOME}/.cache/hydraia/plugin-root" 2>/dev/null)}"
   [ -n "$ROOT" ] || ROOT="$(ls -d "${HOME}/.claude/plugins/cache/hydraia/hydraia/"*/ 2>/dev/null | sort -V | tail -1)"
   ```
2. Start it in the background so it keeps running:
   `node "$ROOT/dashboard/server.js" $ARGUMENTS`
3. It prints `Hydraia dashboard running at http://127.0.0.1:<port>`. Show me that
   URL and open it in my browser (`open` on macOS, `xdg-open` on Linux, `start` on
   Windows). Tell me to stop it with Ctrl-C (or by ending the background process).

If Node is not installed, say so and point me at `/hydraia:doctor`. Never bind to
anything other than `127.0.0.1`.
