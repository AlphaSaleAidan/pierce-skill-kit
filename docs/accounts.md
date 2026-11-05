# Separate Claude accounts for separate purposes

If you have more than one Claude account (say a personal one and a work or client one, each with its own login and
billing), `claude-acct` keeps them apart while sharing your setup. **Each account must be its own legitimately owned
and paid account; check Anthropic's terms for your plan.** This is for keeping work separate, not for getting around
usage limits: an account is picked when a session starts, and nothing moves a running session to another account.

```sh
claude-acct add work           # creates ~/.claude-work, shares your setup into it, opens Claude: type /login
claude-acct                    # pick an account (shows each one's last 5-hour / weekly usage) and start Claude
claude-acct list               # accounts + usage
claude-acct run work           # start Claude on the work account ("main" = ~/.claude)
claude-tab ~/code/client-a -n client-a -a work   # a project tab that runs on the work account
```

- **What's shared** (symlinked from `~/.claude`): skills, `CLAUDE.md`, agents, commands, settings, plugins and project
  memory. **Never shared:** the login (`.credentials.json`), `.claude.json`, caches, locks and per-account state.
- **Usage numbers** are the 5-hour and weekly windows Claude Code itself reports to the status line (`rate_limits`).
  The kit statusline saves them per account each time it draws, so an account shows "no data yet" until you've used it
  with the statusline installed (`mods/install.sh statusline`). No login token is read and no private API is called.
- **Start on the least-used account** (route mod, `sh mods/route/install.sh`): `claude-pick` shows a menu sorted by
  weekly %, then 5-hour % (Enter = least used); `claude-pick auto -p "..."` skips the menu; `claude-pick order` prints
  the config folders least-used first for scripts. It uses the same saved status-line numbers; an account with no
  numbers yet sorts last. Windows: these run on your server, so `ssh box claude-pick` (see [windows.md](windows.md)).
- **Remove an account:** sign out in it (`/logout`), then delete `~/.claude-<name>`.
