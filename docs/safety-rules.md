# Safety rules: what the kit enforces, and what's on you

[RULES.md](../RULES.md) is the full sheet. This page says which rules a tool enforces for you and which only
hold because Claude reads them.

| Rule | Enforced by |
|---|---|
| One tab per project | `claude-tab` refuses a duplicate name, folder or resume id (exit 3) |
| Reports go one way | `report` is the only command; it types into the lead window and logs |
| No stuck tab goes unnoticed | `tab-watch` cron |
| ≤N heavy jobs, low priority, RAM floor | `heavy` (file locks + `nice` + MemAvailable check) |
| The lead manages, doesn't build | optional hook `hooks/lead-no-worker-agents.sh` |
| Everything else (sends, deploys, spend, secrets, pkill) | the rules in CLAUDE.md. Claude follows them; nothing technical stops it |

## Make the "Claude follows them" rules sturdier
- Run tabs without blanket permission skipping, so sends/deploys still prompt.
- Add Claude Code `permissions.deny` entries for commands you never want run unattended (e.g. `git push origin main`).
- Keep secrets in one `chmod 700` folder with a README index; give Claude the path, not the value.

## The lead hook
Blocks the lead from spawning worker subagents (so project work lands in project tabs, where it's visible).
Subagents whose prompt starts with `READ-ONLY` (and the read-only `Explore` agent) are allowed.
`mods/install.sh hook lead-guard` sets it up; or add it to `~/.claude/settings.json` yourself:

```json
{ "hooks": { "PreToolUse": [ { "matcher": "Agent|Task",
  "hooks": [ { "type": "command", "command": "~/.config/pierce-skill-kit/hooks/lead-no-worker-agents.sh" } ] } ] } }
```
It only acts in the lead's own window (`hub:Lead`); project tabs and any other Claude, even one started in the
lead's folder, can use subagents freely. Needs `jq`.
