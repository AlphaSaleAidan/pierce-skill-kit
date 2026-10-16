---
name: claude-accounts
description: Pick the right one of your separate Claude Code accounts (e.g. personal vs work vs a client's) for a session, project tab or headless job, and read each account's usage. Use when starting background/headless claude jobs (cron, scripts, `claude -p`), opening a project tab that belongs to a specific account, when someone asks which account to use or how much usage is left, or when adding an account to the machine.
---

# Claude accounts

Thin rules on top of the kit's `claude-acct` tool (full docs: `docs/accounts.md`). Each account lives in its
own config dir (`~/.claude` = main, `~/.claude-<name>` for the rest) with its own login; skills, `CLAUDE.md`,
settings and memory are shared by symlink.

**Each account must be its own legitimately owned/paid account; check Anthropic's terms for your plan.**
Accounts are for keeping separate purposes apart (personal / work / a client who pays for their own seat),
not for stretching usage limits. There is no automatic switching when an account hits a limit, and this skill
never adds one.

| Need | Command |
|---|---|
| See every account's last 5-hour / weekly % | `claude-acct list` |
| Start Claude on a specific account | `claude-acct run <name> [claude args]` (`main` = `~/.claude`) |
| A project tab on a specific account | `claude-tab <dir> -n <Project> -a <name>` |
| A headless job on a specific account | `claude-acct run <name> -p "..."` |
| Add an account | `claude-acct add <name>`, then `/login` in the Claude that opens |

## Rules
- **Pick by purpose, not by headroom.** A job runs on the account whose work it is: client-a's repo on the
  account client-a pays for, personal projects on yours. Put the mapping in your `CLAUDE.md` once
  (e.g. "client-a/* → account `client-a`") so cron jobs and tabs follow it.
- **New cron/scripted jobs name their account explicitly** (`claude-acct run <name> -p`), never a bare
  `claude` that silently lands on whatever account the shell happens to point at.
- **Usage numbers come only from Claude Code's own `rate_limits`** (saved by the kit statusline). Never read
  login tokens or call undocumented endpoints to get them. "no data yet" just means that account hasn't
  drawn a status line since the statusline mod was installed.
- **An account near its limit:** tell the human and wait, or move to work that doesn't need it. Don't
  re-route that account's work onto another account.
- Subagents run on the parent session's account. Work that belongs to another account is a separate
  session on that account, not a subagent.
- If two accounts show the same login email, the second `/login` never happened: open that account and sign in.
- Never print token or credential values; compare logins by email only.

Needs: this kit (`claude-acct`, `claude-tab`), the statusline mod for usage numbers, `jq`.
