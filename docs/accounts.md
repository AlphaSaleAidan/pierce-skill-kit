# Separate Claude accounts for separate purposes

If you have more than one Claude account (say a personal one and a work or client one, each with its own login and
billing), `claude-acct` keeps them apart while sharing your setup. **Use only accounts you're entitled to use, each
its own login and plan, and follow your plan's terms.** `claude-pick` just starts you on the one with the most room
left; it reads no login, calls no API, and never moves a running session to another account.

```sh
claude-acct add work           # creates ~/.claude-work, shares your setup into it, opens Claude: type /login
claude-acct                    # pick an account (shows each one's last 5-hour / weekly usage) and start Claude
claude-acct list               # accounts + usage
claude-acct run work           # start Claude on the work account ("main" = ~/.claude)
claude-tab ~/code/client-a -n client-a -a work   # a project tab that runs on the work account
```

- **What's shared** (symlinked from `~/.claude`): skills, `CLAUDE.md`, agents, commands, settings, plugins and project
  memory. **Never shared:** the login (`.credentials.json`), `.claude.json`, caches, locks and per-account state.
- **Which folders are accounts:** `~/.claude` (main) and each `~/.claude-<name>` that holds a Claude login
  (`.credentials.json` or `.claude.json`) or was made by `claude-acct add`. Other tools' folders such as
  `~/.claude-flow` are never listed or shared into. Only file names are checked; no login is read.
- **Usage numbers** are the 5-hour and weekly windows Claude Code itself reports to the status line (`rate_limits`).
  The usage status line (`sh mods/usage/install.sh`) saves them per account each time it draws, so an account shows
  "no data yet" until you've used it with that installed. No login token is read and no private API is called.
- **Start on the account with the most room** (route mod, `sh mods/route/install.sh`): `claude-pick` shows a menu
  sorted by weekly %, then 5-hour % (Enter = the top one); `claude-pick auto -p "..."` skips the menu;
  `claude-pick order` prints the config folders in that order for scripts. An account at 95% or more of its 5-hour
  or weekly window is **full**: it goes last, `auto` never picks it and says why
  (`work: 5h at 100%, resets in 2h, skipped`). If every account is full, `auto` says which resets first and exits 1
  without starting Claude. An account with no numbers yet sorts after those with numbers; with no numbers at all it
  says so and `auto` starts main. With the route mod installed, plain `claude-acct` opens the same menu.
  Works on Linux and macOS. Windows: these run on your server, so from PowerShell run
  `ssh -t me@my-server '~/.local/bin/claude-pick'` (`-t` gives the menu a terminal; the full path is needed because a
  one-command ssh login often skips `~/.local/bin` on PATH). See [windows.md](windows.md).
- **Remove an account:** sign out in it (`/logout`), then delete `~/.claude-<name>`.

## What it looks like
The status line with three accounts (`▶` = the account this tab runs on; colours: green, yellow over 60%, red over 85%):

```text
▶ main  5h ▰▰▱▱▱ 40% ↻2h   week ▰▰▰▰▰ 91% ↻1d1h
  work  5h ∞   week ▰▱▱▱▱ 10% ↻3d4h
  spare  5h –   week ▰▰▰▱▱ 52% ↻6d   (old: 3d ago)
```

`∞` = no 5-hour limit (you list the account in `LK_USAGE_NO_5H`), `5h –` = Claude Code sent no 5-hour window,
`(old: 3d ago)` = saved over 6 hours ago, shown dimmed: open that account once to refresh it.

`claude-pick`:

```text
  1) work     week 10%  5h 0%
  2) main     week 60%  5h 40%
  3) alpha    week 20%  5h 100%
     full: 5h at 100%, resets in 2h
Account number (Enter = most room):
```

(Trimmed to fit a phone: in a terminal each row also shows how old its numbers are, e.g. `(2h ago)`, and row 1
ends with `<- most room`.)

Before any account has numbers:

```text
No usage numbers yet: install the usage status line (sh mods/usage/install.sh) and open each account once.
  1) main     week ?    5h ?
  2) work     week ?    5h ?
Account number (Enter = 1):
```
