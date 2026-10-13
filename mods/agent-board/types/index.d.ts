export type AgentRow = {
  id: string
  type: string
  model: string
  task: string
  doing: string
  calls: number
  recent: boolean[] // last 6 tool results, true = error
  repeats: number // same call made back to back
  asking: boolean
  startedAt: number
  doneAt: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'agent-board': { agents: AgentRow[]; isHidden: boolean }
  }
}
