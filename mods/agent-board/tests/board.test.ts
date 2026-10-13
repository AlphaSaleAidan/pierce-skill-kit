import { expect, mock, test } from 'claude-code/testing'

import { describe as say, difficulty, isTopical, promptsFromTranscript, relayText, titlePrompt } from '../hooks/register'
import type { AgentRow } from '../types'

const row = (p: Partial<AgentRow>): AgentRow => ({
  id: 'a', type: 'reviewer', model: 'sonnet-5-5', task: 't', doing: '', calls: 0,
  recent: [], repeats: 0, asking: false, startedAt: 0, doneAt: null, ...p,
})

test('difficulty goes green → yellow → red', async () => {
  expect(difficulty(row({}), 1000)).toBe('green')
  expect(difficulty(row({ recent: [true] }), 1000)).toBe('yellow')
  expect(difficulty(row({ recent: [true, true] }), 1000)).toBe('red')
  expect(difficulty(row({ repeats: 2 }), 1000)).toBe('yellow')
  expect(difficulty(row({ asking: true }), 1000)).toBe('red')
})

test('describe says what the agent is doing', async () => {
  expect(say('Read', { file_path: '/home/me/x/src/auth.ts' })).toBe('reading src/auth.ts')
  expect(say('Bash', { command: 'npm test', description: 'Run tests' })).toBe('Run tests')
  expect(say('mcp__agent-board__ask', { question: 'Which DB?' })).toBe('asking: Which DB?')
})

test('a spawned agent shows on the board with its model and current action', async ($, on) => {
  mock.clock(on)
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'a1' }))
  on('tool.call', () => ({ result: 'ok' }))
  await $.agent.spawn({ prompt: 'review', description: 'Review auth diff', subagentType: 'reviewer' } as never)
  await $.tool.call({ tool: 'Read', file_path: '/home/me/x/src/auth.ts', agentId: 'a1' } as never)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'agent-board', surface, component: 'AbovePrompt', props: {} } as never)
    expect(await ui.find({ type: 'Text', text: /reading src\/auth\.ts/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /sonnet-5-5/ })).toBeDefined()
    await ui.unmount()
  }
})

test('title prompt favors the latest topic and keeps an unchanged title', async () => {
  const p = titlePrompt(['fix the mac crashes', 'build the hub mod', 'arrow keys stuck in hub'], 'Mac Crash Cleanup')
  expect(p).toContain('3. arrow keys stuck in hub')
  expect(p).toContain('Current title: "Mac Crash Cleanup"')
})

test('transcript seeding keeps topical user prompts only', async () => {
  const lines = [
    JSON.stringify({ type: 'user', message: { content: 'build a hub mod for all my projects' } }),
    JSON.stringify({ type: 'user', message: { content: 'try now' } }),
    JSON.stringify({ type: 'user', isMeta: true, message: { content: 'meta stuff that is long enough' } }),
    JSON.stringify({ type: 'user', message: { content: [{ type: 'text', text: 'rename sessions by topic please' }] } }),
    '{"type":"user","message":{"content":"cut off',
  ].join('\n')
  expect(promptsFromTranscript(lines)).toEqual(['build a hub mod for all my projects', 'rename sessions by topic please'])
})

test('relay text names the lead session and says how to reach it', async () => {
  const t = relayText({ sessionId: 'x', name: 'Lead' })
  expect(t).toContain('SendMessage (to: "Lead")')
})

test('lead and report lines never become a session title', async () => {
  expect(isTopical('Brief from the lead: read ~/.pierce-skill-kit/briefs/x.md')).toBe(false)
  expect(isTopical('[REPORT done] acme-app (acme-app): fixed')).toBe(false)
  expect(isTopical('build the client portal onboarding screens')).toBe(true)
})
