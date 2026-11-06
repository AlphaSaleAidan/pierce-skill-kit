# Mods: Claude Code plugins, status line and hooks

The Claude Code mods that run alongside the lead + tabs setup. Each installs with one command and uninstalls with
`--uninstall`; restart Claude Code after either. Needs `jq`. The three Claude Code plugins (agent-board, model-map, projects-hub) validate and pass their tests
(`claude plugin validate <dir>`, `claude plugin test <dir>`) on Claude Code 2.1.296, also in a clean container.

- **agent-board**: A live board above the prompt: every subagent's model, task and current action, coloured green/yellow/red by how much it's struggling. Adds an `ask` tool (any agent can ask you a clarifying question with options), topic-based session titles, a server-overload warning, and `/lead-here <name>` to mark the lead so other sessions get a relay note pointing at it. `/board` hides it.

  Install: `mods/install.sh agent-board`

- **model-map**: Remap subagent models live, no restart: `/models set haiku <model-id>`, `/models default sonnet`, `/models unset haiku`, `/models`. Kept across sessions.

  Install: `mods/install.sh model-map`

- **projects-hub**: `/hub` opens one pane with your active git projects, recent Claude sessions (live ones marked), your open PRs and listening services. Arrows + Enter open a project or resume a session in a tmux pane beside you.

  Install: `mods/install.sh projects-hub`

- **statusline** (usage bars): Folder, branch, model, then 5-hour + weekly bars per account. Linux and macOS. No login read, no private API. [Sample](../docs/accounts.md#what-it-looks-like)

  Install: `sh mods/usage/install.sh`

- **skill-recommender**: On a substantial prompt, or when a task fails twice, Claude asks you once: "Switch to `<skill>`?" for an installed skill that fits better. Local keyword match over the skill index, no API; quiet on short replies; logs answers for tuning. [README](skill-recommender/README.md)

  Install: `mods/install.sh skill-recommender`

- **bridge**: Your local Claude Code talks to the server's lead over SSH: `bridge send` / `inbox` / `sync`, an MCP server (send_to_lead, read_inbox, share_context, pull_context), a shared context folder that never syncs secrets, optional locked-down key. Plus a file store for big files (100 MB each): `bridge files push` / `pull` / `share`. [docs/bridge.md](../docs/bridge.md)

  Install: `sh mods/bridge/bridge setup me@my-server` (Windows: `bridge.ps1 setup`)

- **route**: `claude-pick`: start Claude on the account with the most room; skips any at 95%+ and says when it resets. No login read, no API call. [Details](../docs/accounts.md)

  Install: `sh mods/route/install.sh`

- **brain-loop**: The Obsidian + Opus + Jev loop: a linked vault of projects, people, asks, decisions and plans (Obsidian-compatible, your edits survive rebuilds), report triage that writes the confident answers into plans and asks the lead about the rest, plan compliance grading, stuck-report and overdue-checkpoint alerts, MCP tools (`brain`, `brain_open`, `brain_mark`), a /brain graph page and a SessionStart hook. Needs python3; Jev optional and capped. [README](brain-loop/README.md)

  Install: `mods/install.sh brain-loop`

- **lead-guard** hook: Stops the lead doing project work with its own subagents (READ-ONLY research allowed). Needs the kit's core install.

  Install: `mods/install.sh hook lead-guard`

- **review-gate** hook: Blocks `pm2`/`systemctl` `restart`/`reload` of apps you list until a recent independent review is recorded.

  Install: `mods/install.sh hook review-gate`

- **mail-no-links** hook: Refuses mail sends/drafts with links through a connector that rewrites links. Give it your mail tool names.

  Install: `mods/install.sh hook mail-no-links 'mcp__mail__send_message|mcp__mail__create_draft'`

- **retitle-sessions** tool: Backfills topic titles for past sessions (one small Haiku call each).

  Install: `python3 mods/tools/retitle-sessions.py --dry --limit 5`

## How it installs
- Plugin mods are copied to `~/.config/pierce-skill-kit/mods/<name>` and added to `CLAUDE_CODE_PLUGIN_DIRS` in your
  Claude `settings.json` (`$CLAUDE_CONFIG_DIR/settings.json` if you set that). A `.bak` is written before every edit.
- The status line sets `statusLine` to `~/.config/pierce-skill-kit/mods/statusline/statusline.sh`.
- Hooks are copied to `~/.config/pierce-skill-kit/hooks/` and added under `hooks.PreToolUse`.

## Config (env vars, all optional)
- `LK_HOME`: agent-board (where `lead.json` lives). Default: `~/.pierce-skill-kit`
- `LK_CLAUDE`: projects-hub (command it opens in a pane). Default: `claude`
- `HUB_ROOTS`: projects-hub: colon-separated globs of repos. Default: `~/*/.git`
- `HUB_CACHE`: projects-hub + statusline: snapshot file. Default: `~/.cache/projects-hub.json`
- `STATUSLINE_EXTRA`: statusline: a command whose output joins line 1. Default: none
- `LK_USAGE_NO_5H`: statusline: accounts with no 5-hour limit, shown as ∞ (e.g. `"main work"`); read from the kit config as plain text, never run. Default: none (a missing 5-hour window shows `5h –`)
- `LK_FILES_SHARE`: bridge (server): `1` turns on `bridge files share` links. Default: off
- `REVIEW_GATED`: review-gate: regex of app names to guard (unset = off). Default: none
- `REVIEW_RESTART`, `REVIEW_MARKERS`, `REVIEW_MAX_AGE_MIN`: review-gate. Default: `(pm2|systemctl) +(restart|reload)`, `/tmp`, `90`
- `BRAIN_*`: brain-loop: vault, inputs, router dir, Jev cap ([its README](brain-loop/README.md#inputs-all-from-the-config)). Default: under `$LK_HOME`

Set them in `settings.json` under `env`, or in your shell profile.

## Requirements and limits
- projects-hub: Linux (`ss`, `/proc`), `gh` logged in for PRs, Claude running inside tmux to open panes.
- agent-board's health check reads `/proc` (Linux). Thresholds are at the top of `agent-board/bin/health.sh`.
- Hooks need `jq`.

## Not included, and why
- A usage meter that reads your login or calls a private API: `claude-pick` (route mod) and the usage status line only use what Claude Code passes to the status line.
- Project-specific automations (content engines, revenue tools, app-store scripts, backups, experiments): tied to
  one business and don't generalize.

## Everything else this setup runs: `mods/extras.sh`
One command installs the rest, asking before each group (`--yes` for all, `--list` to only print the commands):

- **Official plugins**: superpowers, hookify, hyperframes, claude-md-management, session-report, security-guidance

  Source: [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)

- **Ponytail**: "lazy senior dev" mode: a SessionStart hook that pushes the simplest working solution

  Source: [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) · MIT

- **Service plugins**: vercel, stripe, shippo, discord, telegram; vapi-voice-ai; watch (video understanding)

  Source: official marketplace · [VapiAI/skills](https://github.com/VapiAI/skills) · [bradautomates/claude-video](https://github.com/bradautomates/claude-video)

- **Anthropic skills**: the anthropics/skills marketplace (pick skills with `/plugin`)

  Source: [anthropics/skills](https://github.com/anthropics/skills)

- **MCP servers**: playwright, context7, memory, sequentialthinking, higgsfield (sign-in on first use; generation is paid). 21st.dev needs a paid key: printed, not installed

  Source: each project's own repo

- **Jumping Rope**: `ROPE.md` live session log that survives compaction, as a skill

  Source: [AlphaSaleAidan/jumping-rope](https://github.com/AlphaSaleAidan/jumping-rope) · MIT

- **claude-usage MCP**: lets Claude see its own session/weekly usage and stick to a budget

  Source: [AlphaSaleAidan/claude-usage-mcp](https://github.com/AlphaSaleAidan/claude-usage-mcp) · MIT

- **Ruflo + overlay**: ruvnet's orchestration + memory layer (`npx ruflo@latest init` in your home folder) plus this kit's 2-line fix so its memory bridge honours `CLAUDE_CONFIG_DIR`

  Source: [ruvnet/ruflo](https://github.com/ruvnet/ruflo) · MIT; details: [ruflo/README.md](ruflo/README.md)

Not installable yet: **VIBAL** (agent + human video timeline over MCP): its public repo is docs only so far.
Multi-model routing playbook (Claude + Codex): [AlphaSaleAidan/opus-5-5-x-gpt-skill-tree](https://github.com/AlphaSaleAidan/opus-5-5-x-gpt-skill-tree).
