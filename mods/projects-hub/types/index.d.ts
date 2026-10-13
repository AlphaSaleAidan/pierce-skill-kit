export type Project = { name: string; dir: string; branch: string; dirty: number; ahead: number | null; age: number }
export type Session = { id: string; title: string; cwd: string; age: number; live: boolean }
export type Service = { port: number; proc: string; cwd: string }
export type PR = { repo: string; n: number; title: string; draft: boolean; updated: string; url: string }
export type Snapshot = { at: number; projects: Project[]; sessions: Session[]; services: Service[]; prs: PR[] }
export type Tab = 'projects' | 'sessions' | 'prs' | 'services'

declare module 'claude-code' {
  interface PluginState {
    'projects-hub': { snap: Snapshot | null; tab: Tab; error: string | null; sel: number }
  }
}
