#!/usr/bin/env node
/*
 * Hydraia dashboard — a local, zero-dependency web server (Node built-ins only).
 *
 *   node dashboard/server.js [port]
 *
 * Binds to 127.0.0.1 ONLY (never exposed to the network) and serves:
 *   GET  /                → the single-page dashboard (dashboard/index.html)
 *   GET  /api/status      → plugin version, skills, agents, hooks, deps, MCP servers
 *   GET  /api/telemetry   → aggregated local usage records (never transmitted)
 *   GET  /api/config      → effective config (defaults + global file)
 *   POST /api/config      → write the global config (~/.config/hydraia/config.json)
 *
 * All data is read from the local filesystem; nothing leaves the machine.
 */
'use strict';
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const HOME = os.homedir();
const GLOBAL_CFG = path.join(HOME, '.config', 'hydraia', 'config.json');
const TELEM_FILE = path.join(HOME, '.cache', 'hydraia', 'telemetry.jsonl');

// Config schema + defaults — keep keys in sync with hooks/config.sh consumers.
const DEFAULTS = {
  maxConcurrentAgents: 6,
  maxTotalAgents: 30,
  specDrive: 'strict',          // strict | relaxed | off
  quickMode: true,
  autoInstallDeps: true,
  codegraphAuto: true,
  runSummary: true,
  telemetry: true,
  telemetryRetentionDays: 90,
  reviewMode: 'double',         // double | single
  selfReviewPasses: 2,
  qaFunctional: true,
  e2eGate: true,
  docsSync: true,
  securityGates: true,
  pdfConversion: true,
  cavemanInternal: true,
  dashboardPort: 7799,
};

function readJSON(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

function effectiveConfig() {
  const glob = readJSON(GLOBAL_CFG) || {};
  const out = Object.assign({}, DEFAULTS);
  for (const k of Object.keys(DEFAULTS)) {
    if (glob[k] !== undefined && glob[k] !== null) out[k] = glob[k];
  }
  return out;
}

function onPath(bin) {
  const dirs = (process.env.PATH || '').split(path.delimiter);
  const names = process.platform === 'win32' ? [bin + '.exe', bin + '.cmd', bin] : [bin];
  for (const d of dirs) {
    for (const n of names) {
      try { fs.accessSync(path.join(d, n), fs.constants.X_OK); return true; } catch {}
    }
  }
  return false;
}

function listSkills() {
  const dir = path.join(PLUGIN_ROOT, 'skills');
  const out = [];
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const f = path.join(dir, e.name, 'SKILL.md');
    let name = e.name, desc = '';
    try {
      const txt = fs.readFileSync(f, 'utf8');
      const m = txt.match(/^---\n([\s\S]*?)\n---/);
      if (m) {
        const nm = m[1].match(/^name:\s*(.+)$/m);
        const dm = m[1].match(/^description:\s*(.+)$/m);
        if (nm) name = nm[1].trim();
        if (dm) desc = dm[1].trim();
      }
    } catch {}
    out.push({ name, desc });
  }
  return out.sort((a, b) => a.name.localeCompare(b.name));
}

function listAgents() {
  const dir = path.join(PLUGIN_ROOT, 'agents');
  const out = [];
  let files = [];
  try { files = fs.readdirSync(dir); } catch { return out; }
  for (const f of files) {
    if (!f.endsWith('.md')) continue;
    let name = f.replace(/\.md$/, ''), desc = '';
    try {
      const txt = fs.readFileSync(path.join(dir, f), 'utf8');
      const m = txt.match(/^---\n([\s\S]*?)\n---/);
      if (m) {
        const nm = m[1].match(/^name:\s*(.+)$/m);
        const dm = m[1].match(/^description:\s*(.+)$/m);
        if (nm) name = nm[1].trim();
        if (dm) desc = dm[1].trim();
      }
    } catch {}
    out.push({ name, desc });
  }
  return out.sort((a, b) => a.name.localeCompare(b.name));
}

// Best-effort read of configured MCP servers from common Claude Code locations.
function listMCP() {
  const names = new Set();
  const candidates = [
    path.join(HOME, '.claude.json'),
    path.join(HOME, '.claude', 'settings.json'),
    path.join(PLUGIN_ROOT, '.mcp.json'),
    path.join(process.cwd(), '.mcp.json'),
  ];
  for (const c of candidates) {
    const j = readJSON(c);
    if (j && j.mcpServers && typeof j.mcpServers === 'object') {
      for (const k of Object.keys(j.mcpServers)) names.add(k);
    }
  }
  return Array.from(names).sort();
}

function status() {
  const plugin = readJSON(path.join(PLUGIN_ROOT, '.claude-plugin', 'plugin.json')) || {};
  const hooks = readJSON(path.join(PLUGIN_ROOT, 'hooks', 'hooks.json')) || {};
  const skills = listSkills();
  const agents = listAgents();
  return {
    version: plugin.version || 'unknown',
    name: plugin.name || 'hydraia',
    skillCount: skills.length,
    agentCount: agents.length,
    skills, agents,
    hookEvents: hooks.hooks ? Object.keys(hooks.hooks) : [],
    mcpServers: listMCP(),
    deps: {
      codegraph: onPath('codegraph'),
      markitdown: onPath('markitdown'),
      node: onPath('node'),
      npm: onPath('npm'),
      python3: onPath('python3') || onPath('python') || onPath('py'),
      git: onPath('git'),
    },
  };
}

function telemetry() {
  let lines = [];
  try { lines = fs.readFileSync(TELEM_FILE, 'utf8').split('\n').filter(Boolean); } catch {}
  const runs = [];
  for (const ln of lines) {
    try { runs.push(JSON.parse(ln)); } catch {}
  }
  const totals = { runs: runs.length, agents: 0, tokensIn: 0, tokensOut: 0, cacheRead: 0 };
  const byModel = {};
  const bySkill = {};
  const byDay = {};
  for (const r of runs) {
    totals.agents += r.agents || 0;
    totals.tokensIn += r.tokensIn || 0;
    totals.tokensOut += r.tokensOut || 0;
    totals.cacheRead += r.cacheRead || 0;
    for (const [m, u] of Object.entries(r.models || {})) {
      byModel[m] = byModel[m] || { in: 0, out: 0 };
      byModel[m].in += (u.in || 0); byModel[m].out += (u.out || 0);
    }
    for (const [s, c] of Object.entries(r.skills || {})) bySkill[s] = (bySkill[s] || 0) + c;
    if (r.ts) {
      const day = new Date(r.ts * 1000).toISOString().slice(0, 10);
      byDay[day] = byDay[day] || { runs: 0, tokensIn: 0, tokensOut: 0 };
      byDay[day].runs += 1; byDay[day].tokensIn += r.tokensIn || 0; byDay[day].tokensOut += r.tokensOut || 0;
    }
  }
  return { totals, byModel, bySkill, byDay, recent: runs.slice(-25).reverse() };
}

function writeConfig(body) {
  const incoming = JSON.parse(body || '{}');
  const cur = readJSON(GLOBAL_CFG) || {};
  for (const k of Object.keys(DEFAULTS)) {
    if (incoming[k] !== undefined) cur[k] = incoming[k];  // only known keys
  }
  fs.mkdirSync(path.dirname(GLOBAL_CFG), { recursive: true });
  fs.writeFileSync(GLOBAL_CFG, JSON.stringify(cur, null, 2) + '\n');
  return effectiveConfig();
}

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(body);
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  try {
    if (req.method === 'GET' && (url === '/' || url === '/index.html')) {
      const html = fs.readFileSync(path.join(__dirname, 'index.html'));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(html);
    }
    if (req.method === 'GET' && url === '/api/status') return send(res, 200, status());
    if (req.method === 'GET' && url === '/api/telemetry') return send(res, 200, telemetry());
    if (req.method === 'GET' && url === '/api/config') return send(res, 200, effectiveConfig());
    if (req.method === 'POST' && url === '/api/config') {
      let body = '';
      req.on('data', (c) => { body += c; if (body.length > 1e6) req.destroy(); });
      req.on('end', () => {
        try { send(res, 200, writeConfig(body)); }
        catch (e) { send(res, 400, { error: String(e && e.message || e) }); }
      });
      return;
    }
    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, 500, { error: String(e && e.message || e) });
  }
});

const port = parseInt(process.argv[2] || process.env.HYDRAIA_DASHBOARD_PORT || effectiveConfig().dashboardPort, 10) || 7799;
server.listen(port, '127.0.0.1', () => {
  const u = `http://127.0.0.1:${port}`;
  process.stdout.write(`Hydraia dashboard running at ${u}\n(local only — bound to 127.0.0.1; Ctrl-C to stop)\n`);
});
server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    process.stderr.write(`Port ${port} is in use — try: node dashboard/server.js ${port + 1}\n`);
    process.exit(1);
  }
  throw e;
});
