import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Snapshot, Tab } from '../types'

const PANE = 'projects-hub'
const snap = atom({ plugin: 'projects-hub', key: 'snap' } as const, null)
const tab = atom({ plugin: 'projects-hub', key: 'tab' } as const, 'projects')
const error = atom({ plugin: 'projects-hub', key: 'error' } as const, null)
const sel = atom({ plugin: 'projects-hub', key: 'sel' } as const, 0)
const HEADER_ROWS = 2 // tabs row + summary row, above the project list
const TABS: [Tab, string, string][] = [
  ['projects', 'Projects', '1'],
  ['sessions', 'Sessions', '2'],
  ['prs', 'PRs', '3'],
  ['services', 'Services', '4'],
]

export const ago = (s: number) =>
  s < 3600 ? `${Math.round(s / 60)}m` : s < 86400 ? `${Math.round(s / 3600)}h` : `${Math.round(s / 86400)}d`

// Opens Claude in a new pane beside this one (needs Claude running inside tmux; `lead` and `claude-tab` do this).
async function openInPane($: EngineInterface, dir: string, args: string[], label: string) {
  const claude = (await $.env.get('LK_CLAUDE')) ?? 'claude'
  const r = await $.process.run(['tmux', 'split-window', '-h', '-c', dir, claude, ...args])
  if (r.exitCode !== 0) {
    $.ui.toast(`Can't split: start Claude inside tmux. ${r.stderr.trim().slice(0, 80)}`)
    return
  }
  await $.process.run(['tmux', 'select-layout', 'tiled'])
  $.ui.toast(`Opened ${label} beside this session`)
}

// The selectable rows of a tab: what the arrows move through and Enter / o runs.
export function rowsFor($: EngineInterface, s: Snapshot, t: Tab): { key: string; run: () => Promise<void> }[] {
  if (t === 'projects') return s.projects.map(p => ({ key: `proj-${p.name}`, run: () => openInPane($, p.dir, [], p.name) }))
  if (t === 'sessions')
    return s.sessions.map(x => ({
      key: `sess-${x.id}`,
      run: async () => {
        if (x.live) $.ui.toast(`"${x.title}" is already open in another terminal`)
        else await openInPane($, x.cwd, ['--resume', x.id], x.title)
      },
    }))
  return []
}

async function refresh($: EngineInterface) {
  try {
    const r = await $.process.run(['python3', `${$.plugin.root}/bin/gather.py`], { timeoutMs: 90_000 })
    if (r.exitCode !== 0) throw new Error(r.stderr.slice(0, 200) || `exit ${r.exitCode}`)
    const s: Snapshot = JSON.parse(r.stdout)
    await update($, snap, () => s)
    await update($, error, () => null)
    $.ui.status(`hub: ${s.sessions.length} sessions · ${s.prs.length} PRs`)
  } catch (err) {
    await update($, error, () => String(err))
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'hub', description: 'Projects, live sessions, PRs and services in one pane' })
    void $.ui.close({ id: PANE }) // ponytail: never leave a stale pane after reload; /hub reopens
    void refresh($)
    $.clock.every(120_000, () => refresh($)) // ponytail: 2-min poll; gather takes ~12s
    return next(e)
  })

  on('command.run', { command: 'hub' }, async $ => {
    if ((await $.ui.panes()).some(p => p.id === PANE)) {
      await $.ui.close({ id: PANE })
      return { text: 'Projects hub closed.' }
    }
    await $.ui.open({ id: PANE, title: 'Projects hub', focus: true, closeOnEscape: true })
    void refresh($)
    return { text: 'Hub: 1 Projects / 2 Sessions, arrows move, Enter opens it beside this terminal, /hub again closes.' }
  })

  // Arrows scroll a pane by default; on the Projects and Sessions tabs they move the selection
  // instead, and the window follows so the selected row stays in view.
  on('ui.scroll', { requestId: PANE }, async ($, e, next) => {
    const s = await read($, snap)
    const rows = s ? rowsFor($, s, await read($, tab)) : []
    if (rows.length === 0 || e.origin.kind !== 'person') return next(e)
    const step = Math.sign(e.by) * Math.max(1, Math.round(Math.abs(e.by)))
    const i = Math.min(rows.length - 1, Math.max(0, (await read($, sel)) + step))
    await update($, sel, () => i)
    const r = rows[i]
    if (r) void $.ui.focus({ requestId: PANE, key: r.key }).catch(() => undefined)
    const row = HEADER_ROWS + i
    const offset = Math.max(0, Math.min(e.offset, row, e.contentRows - e.bodyRows), row - e.bodyRows + 1)
    return next({ ...e, offset })
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Markdown } = $.ui.resolve(e)
    const s = await read($, snap)
    const t = await read($, tab)
    const err = await read($, error)

    const tabs = (
      <Box gap={1}>
        {TABS.map(([id, label, key]) => (
          <Button key={`tab-${id}`} label={id === t ? `[${label}]` : label} hotkey={key} onPress={async () => { await update($, tab, () => id); await update($, sel, () => 0) }} />
        ))}
        <Button
          key="open"
          label="Open selected"
          hotkey="o"
          onPress={async () => {
            const r = s ? rowsFor($, s, t)[await read($, sel)] : undefined
            if (r) await r.run()
          }}
        />
        <Button key="refresh" label="Refresh" hotkey="r" onPress={() => refresh($)} />
        <Button key="close" label="Close" hotkey="x" onPress={() => $.ui.close({ id: PANE })} />
      </Box>
    )
    if (!s) return <Box flexDirection="column">{tabs}<Text dimColor>{err ?? 'Loading…'}</Text></Box>

    let body
    if (t === 'projects') {
      const at = Math.min(await read($, sel), s.projects.length - 1)
      body = s.projects.map((p, i) => (
        <Button
          key={`proj-${p.name}`}
          plain
          autoFocus={i === at ? true : undefined}
          label={`${i === at ? '›' : ' '} ${p.name.padEnd(26)} ${p.branch.slice(0, 28).padEnd(28)} ${ago(p.age).padStart(4)}${p.dirty ? `  ${p.dirty} uncommitted` : ''}${p.ahead ? `  ${p.ahead} unpushed` : ''}`}
          onPress={() => openInPane($, p.dir, [], p.name)}
        />
      ))
    } else if (t === 'sessions') {
      const at = Math.min(await read($, sel), s.sessions.length - 1)
      body = s.sessions.map((x, i) => (
        <Button
          key={`sess-${x.id}`}
          plain
          autoFocus={i === at ? true : undefined}
          label={`${i === at ? '›' : ' '} ${x.live ? '●' : ' '} ${x.title.padEnd(48)} ${x.cwd.padEnd(18)} ${ago(x.age).padStart(4)} ago`}
          onPress={() => (rowsFor($, s, 'sessions')[i] ?? { run: async () => undefined }).run()}
        />
      ))
    } else if (t === 'prs') {
      body = <Markdown text={s.prs.map(p => `- **${p.repo}** [#${p.n}](${p.url}) ${p.draft ? '_(draft)_ ' : ''}${p.title} · ${p.updated}`).join('\n')} />
    } else {
      body = s.services.map(x => (
        <Text>
          <Text bold>:{String(x.port).padEnd(5)}</Text> {x.proc.slice(0, 16).padEnd(16)} <Text dimColor>{x.cwd}</Text>
        </Text>
      ))
    }

    return (
      <Box flexDirection="column">
        {tabs}
        <Text dimColor>
          {s.projects.length} active projects (14d) · {s.sessions.length} live sessions · {s.prs.length} open PRs · {s.services.length} services · {err ? `refresh failed: ${err}` : `updated ${ago(Math.floor(Date.now() / 1000) - s.at)} ago`}
        </Text>
        {body}
      </Box>
    )
  })
}
