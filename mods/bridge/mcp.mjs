#!/usr/bin/env node
// Pierce Skill Kit bridge: a tiny stdio MCP server, no dependencies. Every tool shells out to the bridge CLI next to
// this file (bridge on Mac/Linux, bridge.ps1 on Windows), which talks to the server over ssh.
// Dual-era per modelcontextprotocol.io: legacy clients use the initialize handshake (2025-11-25 and earlier);
// modern clients (2026-07-28) send the version in each request's _meta and may call server/discover.
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';

const here = dirname(fileURLToPath(import.meta.url));
const [CLI, PRE] = process.platform === 'win32'
  ? ['powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(here, 'bridge.ps1')]]
  : ['sh', [join(here, 'bridge')]];
const MODERN = ['2026-07-28'];
const LEGACY = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];
const INFO = { name: 'pierce-bridge', version: '1.0.0' };
const INSTRUCTIONS = 'Talk to the lead Claude session on the server: send_to_lead, then read_inbox for its answers. ' +
  'share_context / pull_context read and write the shared folder (briefs, decisions, reports, memory index, ROPE.md). ' +
  'Secrets (.env, keys, tokens, credentials) never sync.';

const s = (description) => ({ type: 'string', description });
const TOOLS = [
  { name: 'send_to_lead', title: 'Send to lead',
    description: 'Type a message into the lead session on the server. It arrives as "[BRIDGE from <this machine>] ...".',
    inputSchema: { type: 'object', properties: { text: s('The message (one paragraph, under 8 KB)') }, required: ['text'], additionalProperties: false },
    args: (a) => need(a, 'text') && [['send'], a.text] },
  { name: 'read_inbox', title: 'Read inbox',
    description: 'Fetch replies the lead sent with `bridge reply` and show the new ones (marks them read).',
    inputSchema: { type: 'object', properties: { all: { type: 'boolean', description: 'Show every message, not only new ones' } }, additionalProperties: false },
    args: (a) => [a.all === true ? ['inbox', '--all'] : ['inbox'], ''] },
  { name: 'share_context', title: 'Share context',
    description: 'Write one text file into the shared context folder and sync it to the server.',
    inputSchema: { type: 'object', properties: { path: s('Path inside the folder, e.g. briefs/checkout.md'), content: s('Full file content, under 1 MB') }, required: ['path', 'content'], additionalProperties: false },
    args: (a) => need(a, 'path') && typeof a.content === 'string' && [['share', a.path], a.content] },
  { name: 'pull_context', title: 'Pull context',
    description: 'Sync the shared folder, then list its files, or print one file if path is given.',
    inputSchema: { type: 'object', properties: { path: s('Optional: one file to print') }, additionalProperties: false },
    args: (a) => (a.path === undefined || need(a, 'path')) && [a.path ? ['pull', a.path] : ['pull'], ''] },
];
const need = (a, k) => typeof a[k] === 'string' && a[k].trim() !== '';

function run(args, input) {
  return new Promise((resolve) => {
    const p = spawn(CLI, [...PRE, ...args], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    let out = '';
    const kill = setTimeout(() => p.kill(), 120000);
    p.stdout.on('data', (d) => { out += d; });
    p.stderr.on('data', (d) => { out += d; });
    p.on('error', (e) => { clearTimeout(kill); resolve({ code: 1, out: `could not start ${CLI}: ${e.message}` }); });
    p.on('close', (code) => { clearTimeout(kill); resolve({ code, out: out.trim() || (code ? 'failed' : 'ok') }); });
    p.stdin.on('error', () => {});
    p.stdin.end(input);
  });
}

const send = (m) => process.stdout.write(JSON.stringify(m) + '\n');
const reply = (id, result) => send({ jsonrpc: '2.0', id, result });
const fail = (id, code, message, data) => send({ jsonrpc: '2.0', id, error: data ? { code, message, data } : { code, message } });

async function handle(m) {
  if (!m || typeof m !== 'object' || Array.isArray(m) || m.jsonrpc !== '2.0') return fail(null, -32600, 'Invalid Request');
  const { id, method } = m;
  const params = m.params && typeof m.params === 'object' ? m.params : {};
  if (id === undefined || id === null) return; // notifications (notifications/initialized, cancelled, ...) need no answer
  const v = params._meta?.['io.modelcontextprotocol/protocolVersion'];
  if (v !== undefined && !MODERN.includes(v)) return fail(id, -32022, 'Unsupported protocol version', { supported: [...MODERN, ...LEGACY], requested: v });
  const r = v ? { resultType: 'complete' } : {}; // modern results carry resultType
  switch (method) {
    case 'initialize': return reply(id, {
      protocolVersion: LEGACY.includes(params.protocolVersion) ? params.protocolVersion : LEGACY[0],
      capabilities: { tools: {} }, serverInfo: INFO, instructions: INSTRUCTIONS });
    case 'server/discover': return reply(id, { resultType: 'complete', supportedVersions: [...MODERN, ...LEGACY],
      capabilities: { tools: {} }, _meta: { 'io.modelcontextprotocol/serverInfo': INFO }, instructions: INSTRUCTIONS });
    case 'ping': return reply(id, r);
    case 'tools/list': return reply(id, { ...r, tools: TOOLS.map(({ args, ...t }) => t) });
    case 'tools/call': {
      const tool = TOOLS.find((t) => t.name === params.name);
      if (!tool) return fail(id, -32602, `Unknown tool: ${params.name}`);
      const a = tool.args(params.arguments && typeof params.arguments === 'object' ? params.arguments : {});
      if (!a) return reply(id, { ...r, content: [{ type: 'text', text: `Invalid arguments for ${tool.name}: see its inputSchema` }], isError: true });
      const { code, out } = await run(a[0], a[1]);
      return reply(id, { ...r, content: [{ type: 'text', text: out }], isError: code !== 0 });
    }
    default: return fail(id, -32601, `Method not found: ${method}`);
  }
}

createInterface({ input: process.stdin }).on('line', (line) => {
  if (!line.trim()) return;
  let m;
  try { m = JSON.parse(line); } catch { return fail(null, -32700, 'Parse error'); }
  handle(m).catch((e) => fail(m?.id ?? null, -32603, String(e?.message || e)));
});
