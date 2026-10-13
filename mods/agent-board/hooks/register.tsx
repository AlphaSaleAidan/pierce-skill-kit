import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AgentRow } from '../types'

const agents = atom({ plugin: 'agent-board', key: 'agents' } as const, [])
const isHidden = atom({ plugin: 'agent-board', key: 'isHidden' } as const, false)
const ASK = 'mcp__agent-board__ask'

// ponytail: difficulty is a heuristic (recent errors, retries, open question, runtime); tune weights here.
export function difficulty(a: AgentRow, now: number): 'green' | 'yellow' | 'red' {
  if (a.asking) return 'red'
  const score =
    a.recent.filter(Boolean).length * 2 + (a.repeats >= 2 ? 2 : 0) + (now - a.startedAt > 10 * 60_000 ? 1 : 0)
  return score >= 4 ? 'red' : score >= 2 ? 'yellow' : 'green'
}

export function describe(tool: string, input: Record<string, unknown>): string {
  const s = (k: string) => (typeof input[k] === 'string' ? (input[k] as string) : '')
  const file = (s('file_path') || s('path')).split('/').slice(-2).join('/')
  if (tool === 'Bash') return s('description') || `$ ${s('command').slice(0, 60)}`
  if (tool === 'Read') return `reading ${file}`
  if (tool === 'Edit' || tool === 'Write') return `editing ${file}`
  if (tool === 'Grep' || tool === 'Glob') return `searching ${s('pattern').slice(0, 40)}`
  if (tool === 'WebSearch' || tool === 'WebFetch') return `web: ${(s('query') || s('url')).slice(0, 50)}`
  if (tool === 'Agent') return `spawning ${s('description')}`
  if (tool === ASK) return `asking: ${s('question').slice(0, 60)}`
  return tool.replace(/^mcp__/, '')
}

const shortModel = (m: string | undefined) => (m ?? '?').replace(/^claude-/, '').replace(/-\d{8}$/, '')

async function patch($: EngineInterface, id: string, fn: (a: AgentRow) => AgentRow) {
  await update($, agents, list => list.map(a => (a.id === id ? fn(a) : a)))
}

let mainModel = 'main'
const safe = (p: Promise<unknown>) => p.catch(() => undefined)

async function track($: EngineInterface, e: { tool_use_id: string; description: string; subagentType: string; parentModel: string }, r: { model: string; agentId?: string }) {
  mainModel = e.parentModel || mainModel
  const row: AgentRow = {
    id: r.agentId ?? e.tool_use_id,
    type: e.subagentType || 'general-purpose',
    model: shortModel(r.model),
    task: e.description,
    doing: 'starting',
    calls: 0,
    recent: [],
    repeats: 0,
    asking: false,
    startedAt: await $.clock.now(),
    doneAt: null,
  }
  await update($, agents, list => [...list.filter(a => a.id !== row.id), row].slice(-30))
}

// The clarifying-question tool: any agent (main or sub) can ask the person directly.
async function ask($: EngineInterface, input: Record<string, unknown>, id: string | undefined) {
  const q = String(input.question ?? '').trim() || 'Can you clarify?'
  const opts = (Array.isArray(input.options) ? input.options : []).filter((o): o is string => typeof o === 'string').slice(0, 4)
  if (id) await safe(patch($, id, a => ({ ...a, asking: true, doing: `asking: ${q.slice(0, 60)}` })))
  try {
    const who = id ? (await read($, agents)).find(a => a.id === id) : undefined
    const answer = await $.ui.ask(`${who ? `[${who.type}] ` : ''}${q.endsWith('?') ? q : `${q}?`}`, opts.length >= 2 ? opts : undefined)
    return { result: { answer }, text: `The human answered: ${answer}` }
  } catch {
    return { result: { answer: null }, text: 'The human dismissed the question. Use your best judgment and say what you assumed.' }
  } finally {
    if (id) await safe(patch($, id, a => ({ ...a, asking: false })))
  }
}

// Server overload watch: toast on crit (at most every 10 min), status line on warn.
let lastAlert = 0
async function checkHealth($: EngineInterface) {
  const r = await $.process.run(['sh', `${$.plugin.root}/bin/health.sh`])
  const [level = 'ok', ...why] = r.stdout.trim().split(' ')
  const now = await $.clock.now()
  if (level === 'crit' && now - lastAlert > 10 * 60_000) {
    lastAlert = now
    $.ui.toast(`SERVER OVERLOADED:${why.join(' ')} - pause heavy jobs`)
  }
  $.ui.status(level === 'ok' ? undefined : `${level === 'crit' ? 'OVERLOADED' : 'busy'}:${why.join(' ')}`)
}

// Session titles follow the topic: every few main-thread turns Haiku names what the person is working on
// now; the new title is handed back on the next prompt (UserPromptSubmit's sessionTitle).
const recentPrompts: string[] = []
let mainTurns = 0
let currentTitle = ''
let pendingTitle = ''

export const TITLE_EVERY = 3 // ponytail: retitle cadence in main-thread turns
export function titlePrompt(prompts: readonly string[], current: string): string {
  return (
    'Name the topic the user is working on RIGHT NOW in 3-6 plain words, Title Case, no quotes or punctuation at the end. ' +
    'Weight the latest requests most; ignore earlier topics they moved on from.' +
    (current ? ` Current title: "${current}" - repeat it exactly if the topic has not changed.` : '') +
    '\n\nRecent requests, oldest first:\n' +
    prompts.map((p, i) => `${i + 1}. ${p.replace(/\s+/g, ' ').slice(0, 400)}`).join('\n')
  )
}

// Short replies ("yes", "try now") say nothing about the topic.
export const isTopical = (t: string) =>
  t.length >= 15 && !/^[</]|^Caveat:|^\[Request interrupted|^(Brief from the lead|\[REPORT |\[WATCH\])/.test(t) // lead/report lines aren't the topic

// User prompts from transcript lines (JSONL), oldest first.
export function promptsFromTranscript(jsonl: string): string[] {
  const out: string[] = []
  for (const line of jsonl.split('\n')) {
    if (!line.includes('"type":"user"')) continue
    try {
      const m = JSON.parse(line) as { isMeta?: boolean; isSidechain?: boolean; message?: { content?: unknown } }
      if (m.isMeta || m.isSidechain) continue
      const c = m.message?.content
      const text = typeof c === 'string' ? c : Array.isArray(c) ? c.map(b => (b && typeof b === 'object' && 'text' in b ? String(b.text) : '')).join(' ') : ''
      const t = text.replace(/\s+/g, ' ').trim()
      if (isTopical(t)) out.push(t.slice(0, 400))
    } catch {
      // a line cut by the tail read
    }
  }
  return out
}

// After a reload or resume, pick up what the session was about from its transcript's tail.
async function seedPrompts($: EngineInterface) {
  const [id, cwd, cfg, home] = await Promise.all([$.session.id(), $.session.cwd(), $.env.get('CLAUDE_CONFIG_DIR'), $.env.get('HOME')])
  const path = `${cfg ?? `${home}/.claude`}/projects/${cwd.replace(/[^A-Za-z0-9]/g, '-')}/${id}.jsonl`
  const r = await $.process.run(['tail', '-c', '600000', path])
  if (r.exitCode !== 0) return
  recentPrompts.splice(0, recentPrompts.length, ...promptsFromTranscript(r.stdout).slice(-6))
}

// The lead session: a fixed name other sessions message. `/lead-here <name>` in the lead writes
// $LK_HOME/lead.json (default ~/.pierce-skill-kit/lead.json); every other session reads it at start.
export type Lead = { sessionId: string; name: string }
let lead: Lead | null = null
let isLead = false
async function leadFile($: EngineInterface) {
  return `${(await $.env.get('LK_HOME')) ?? `${await $.env.get('HOME')}/.pierce-skill-kit`}/lead.json`
}

async function loadLead($: EngineInterface) {
  const r = await $.process.run(['cat', await leadFile($)])
  if (r.exitCode !== 0) return
  const l = JSON.parse(r.stdout) as Lead
  if (!l.sessionId || !l.name) return
  lead = l
  isLead = l.sessionId === (await $.session.id())
  if (isLead && currentTitle !== l.name) pendingTitle = l.name
}

export function relayText(l: Lead): string {
  return (
    `Relay: the human's lead session on this machine is "${l.name}". When you are blocked, need a decision, or finish a ` +
    `milestone, message it with SendMessage (to: "${l.name}") instead of stopping to wait, then keep working on whatever ` +
    `is clear. It answers for the human or escalates to them. Keep messages to a few lines: what you need, the options, ` +
    `your recommendation.`
  )
}

async function retitle($: EngineInterface) {
  if (isLead) return // the lead keeps its fixed name so other sessions can find it
  if (recentPrompts.length === 0) return
  const r = await $.model.complete({ model: 'haiku', prompt: titlePrompt(recentPrompts, currentTitle), maxTokens: 30, effort: 'low', timeoutMs: 15_000 })
  if (!r.isAnswered) return
  const title = r.text.trim().replace(/^["'\s]+|["'.\s]+$/g, '').slice(0, 60)
  if (title && title !== currentTitle) pendingTitle = title
}

export const register: Register = on => {
  const lastCall = new Map<string, string>()

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'board', description: 'Show or hide the live agent board' })
    await $.command.register({ name: 'lead-here', description: 'Mark this session as the lead other sessions message' })
    await $.tool.register({
      name: 'ask',
      description:
        'Ask the human a clarifying question when you are genuinely blocked or the task is ambiguous, instead of guessing. ' +
        'Subagents may use this. Give 2-4 short options when you can. Returns their answer.',
      inputSchema: {
        type: 'object',
        properties: {
          question: { type: 'string', description: 'One question, ending in a question mark' },
          options: { type: 'array', items: { type: 'string' }, description: '2-4 short answer choices (optional)' },
        },
        required: ['question'],
      },
      isDeferred: false,
    }).catch(() => undefined) // a session started with no tools takes none; keep the rest of startup
    void safe(seedPrompts($))
    void safe(loadLead($))
    void safe(checkHealth($))
    $.clock.every(60_000, () => safe(checkHealth($)))
    return next(e)
  })

  on('command.run', { command: 'lead-here' }, async ($, e) => {
    const name = e.args.trim()
    if (!name) return { text: 'Usage: /lead-here <name other sessions should message, e.g. "Lead">' }
    const l: Lead = { sessionId: await $.session.id(), name }
    const f = await leadFile($)
    await $.process.run(['mkdir', '-p', f.replace(/\/lead\.json$/, '')])
    await $.fs.write(f, JSON.stringify(l))
    lead = l
    isLead = true
    pendingTitle = name
    return { text: `This session is now the lead "${name}". Sessions started from now on get a relay note pointing here.` }
  })

  on('command.run', { command: 'board' }, async $ => {
    const hidden = await update($, isHidden, v => !v).catch(() => false)
    return { text: hidden ? 'Agent board hidden.' : 'Agent board shown.' }
  })

  on('agent.spawn', async ($, e, next) => {
    const r = await next(e)
    if (r.deny !== undefined) return r
    await safe(track($, e, r))
    return r
  })


  // One tool.call hook: serves the ask tool, and tracks what each subagent is doing.
  // Bookkeeping never blocks the call: every failure there is swallowed.
  on('tool.call', async ($, e, next) => {
    const input = e as unknown as Record<string, unknown>
    const id = e.agentId
    if (e.tool === ASK) return ask($, input, id)
    if (!id) return next(e)
    const { tool_use_id: _t, agentId: _a, ...args } = input
    const sig = JSON.stringify(args)
    const repeated = lastCall.get(id) === sig
    lastCall.set(id, sig)
    await safe(patch($, id, a => ({ ...a, doing: describe(e.tool, input), calls: a.calls + 1, repeats: repeated ? a.repeats + 1 : 0 })))
    const r = await next(e)
    await safe(patch($, id, a => ({ ...a, recent: [...a.recent, r.isError === true].slice(-6) })))
    return r
  })

  on('prompt.submit', async ($, e, next) => {
    const text = e.text.trim()
    if (isTopical(text)) recentPrompts.push(text)
    if (recentPrompts.length > 6) recentPrompts.shift()
    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    if (!lead || isLead) return r
    return { sections: [...r.sections, { id: 'agent-board:relay', text: relayText(lead), scope: 'session' as const }] }
  })

  on('classic.UserPromptSubmit', async ($, e, next) => {
    const r = await next(e)
    if (!pendingTitle) return r
    currentTitle = pendingTitle
    pendingTitle = ''
    return { ...r, sessionTitle: currentTitle }
  })

  on('turn.complete', async ($, e, next) => {
    const id = (e as { agentId?: string }).agentId
    if (!id && mainTurns++ % TITLE_EVERY === 0) void safe(retitle($))
    if (id) {
      const now = await $.clock.now()
      await safe(patch($, id, a => ({ ...a, doing: e.isAborted ? 'stopped' : 'done', doneAt: now })))
    }
    return next(e)
  })


  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const now = await $.clock.now()
    const list = (await read($, agents)).filter(a => a.doneAt === null || now - a.doneAt < 120_000)
    if (list.length === 0 || (await read($, isHidden)) || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const models = new Map<string, number>()
    for (const a of list) models.set(a.model, (models.get(a.model) ?? 0) + 1)
    return (
      <Box flexDirection="column">
        <Text dimColor>
          agents · main {shortModel(mainModel)} → {[...models].map(([m, n]) => `${m} ×${n}`).join(' · ')}
        </Text>
        {list.map(a => {
          const done = a.doneAt !== null
          const color = done ? undefined : difficulty(a, now)
          return (
            <Text wrap="truncate-end">
              <Text dimColor={done}>{done ? '✓' : '●'} {a.type} </Text>
              <Text dimColor>({a.model}) {a.task.slice(0, 40)} › </Text>
              <Text color={color} dimColor={done}>{a.doing}</Text>
              <Text dimColor>  {a.calls} calls{a.recent.some(Boolean) ? `, ${a.recent.filter(Boolean).length} errs` : ''}</Text>
            </Text>
          )
        })}
      </Box>
    )
  })
}
