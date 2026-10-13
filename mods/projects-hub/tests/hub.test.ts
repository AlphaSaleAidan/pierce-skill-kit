import { expect, mock, test } from 'claude-code/testing'

const SNAP = {
  at: 0,
  projects: [{ name: 'acme-app', dir: '/home/me/acme-app', branch: 'feat/checkout', dirty: 3, ahead: 1, age: 120 }],
  sessions: [{ id: 'abc-123', title: 'Checkout Fix', cwd: '/home/me/acme-app', age: 7200, live: false }],
  services: [{ port: 3000, proc: 'node', cwd: '~/acme-app' }],
  prs: [{ repo: 'acme-app', n: 12, title: 'fix(checkout): coupon total', draft: false, updated: '2026-10-03', url: 'https://github.com/example/acme-app/pull/12' }],
}

test('hub loads the snapshot and switches tabs', async ($, on) => {
  const runs: string[][] = []
  mock.env(on, {}) // LK_CLAUDE unset -> plain `claude`
  on('process.run', (_$, e) => (runs.push([...e.argv]), { value: { exitCode: 0, stdout: JSON.stringify(SNAP), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'projects-hub', surface, component: 'Pane', requestId: 'projects-hub', props: { title: 'Projects hub' } } as never)
    await ui.press({ key: 'tab-projects' })
    await ui.press({ key: 'refresh' })
    expect(await ui.find({ key: 'proj-acme-app' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /1 open PRs/ })).toBeDefined()
    await ui.press({ key: 'proj-acme-app' })
    runs.length = 0
    await ui.press({ key: 'open' })
    expect(runs.some(a => a.join(' ').startsWith('tmux split-window -h -c /home/me/acme-app'))).toBe(true)
    runs.length = 0
    await ui.press({ key: 'tab-sessions' })
    await ui.press({ key: 'sess-abc-123' })
    expect(runs.some(a => a.join(' ') === 'tmux split-window -h -c /home/me/acme-app claude --resume abc-123')).toBe(true)
    await ui.press({ key: 'tab-services' })
    expect(await ui.find({ type: 'Text', text: /3000/ })).toBeDefined()
    await ui.unmount()
  }
})
