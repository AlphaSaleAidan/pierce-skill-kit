import type { Engine, Register } from 'claude-code'

// Live model remapping for sub-agents. The map lives in $.store (kept across sessions),
// so a change applies to the very next Agent launch — no restart.
//   /models                         show the map and the default
//   /models set haiku claude-haiku-5-5   send every "haiku" sub-agent to that model id
//   /models unset haiku             drop a mapping
//   /models default sonnet          model for sub-agents that name none (forks always inherit)
//   /models default off             clear the default
const MAP_KEY = 'map'
const DEFAULT_KEY = 'default'
const ID = /^[A-Za-z0-9._:\-\/\[\]]{1,120}$/

type ModelMap = Record<string, string>

export function remap(model: string | undefined, map: ModelMap, fallback: string | undefined): string | undefined {
  if (model === undefined) return fallback
  return map[model] ?? model
}

export function parse(args: string): { cmd: string; a?: string; b?: string } {
  const [cmd = '', a, b] = args.trim().split(/\s+/).filter(Boolean)
  return { cmd: cmd.toLowerCase(), a, b }
}

export function describe(map: ModelMap, fallback: string | undefined): string {
  const rows = Object.entries(map).map(([from, to]) => `  ${from} -> ${to}`)
  return [
    rows.length ? 'Sub-agent model map:' : 'Sub-agent model map: (empty — aliases resolve normally)',
    ...rows,
    `Default for sub-agents that name no model: ${fallback ?? '(none — agent definition, then parent)'}`,
  ].join('\n')
}

async function load($: Engine): Promise<{ map: ModelMap; fallback: string | undefined }> {
  return {
    map: ((await $.store.get(MAP_KEY)) as ModelMap | undefined) ?? {},
    fallback: (await $.store.get(DEFAULT_KEY)) as string | undefined,
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'models',
      description: 'Remap sub-agent models live: /models set haiku claude-haiku-5-5 · /models default sonnet · /models',
    })
    const { map } = await load($)
    if (Object.keys(map).length) $.ui.status(`models: ${Object.entries(map).map(([f, t]) => `${f}→${t}`).join(', ')}`)
    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const { map, fallback } = await load($)
    const model = remap(e.model, map, fallback)
    return model === e.model ? next(e) : next({ ...e, model })
  })

  on('command.run', { command: 'models' }, async ($, e) => {
    const { cmd, a, b } = parse(e.args)
    const { map, fallback } = await load($)

    if (cmd === 'set') {
      if (!a || !b || !ID.test(a) || !ID.test(b)) return { text: 'Usage: /models set <alias-or-id> <model-id>' }
      const next = { ...map, [a]: b }
      await $.store.set(MAP_KEY, next)
      $.ui.status(`models: ${Object.entries(next).map(([f, t]) => `${f}→${t}`).join(', ')}`)
      $.ui.toast(`Sub-agents asking for ${a} now run on ${b}`)
      return { text: `Set: ${a} -> ${b}. Applies to the next sub-agent launch.\n\n${describe(next, fallback)}` }
    }
    if (cmd === 'unset') {
      if (!a || !(a in map)) return { text: `No mapping for ${a ?? '(nothing)'}.\n\n${describe(map, fallback)}` }
      const next = { ...map }
      delete next[a]
      await $.store.set(MAP_KEY, next)
      $.ui.status(Object.keys(next).length ? `models: ${Object.entries(next).map(([f, t]) => `${f}→${t}`).join(', ')}` : undefined)
      return { text: `Removed ${a}.\n\n${describe(next, fallback)}` }
    }
    if (cmd === 'default') {
      if (!a) return { text: 'Usage: /models default <alias-or-id> | off' }
      if (a.toLowerCase() === 'off') {
        await $.store.delete(DEFAULT_KEY)
        return { text: `Default cleared.\n\n${describe(map, undefined)}` }
      }
      if (!ID.test(a)) return { text: 'That model name has characters a model id never has.' }
      await $.store.set(DEFAULT_KEY, a)
      return { text: `Default set to ${a}.\n\n${describe(map, a)}` }
    }
    return { text: describe(map, fallback) }
  })
}
