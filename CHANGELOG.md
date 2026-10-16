# Changelog

Newest first. **Run this** lines are for people who already installed the kit.
Watch this repo → Custom → Releases to get notified.

## v0.4.0 (2026-10-16)
### Added
- **4 skills** (22 in all): `claude-accounts` (which of your separate, legitimately owned accounts a tab or job runs
  on; usage from Claude Code's own data, no automatic switching), `collab-sandbox` (a walled-off workspace for a
  collaborator, under their own Claude login), `sales-appointment-prep` (same-day site + deck + demo phone agent for a
  booked meeting), `person-into-existing-scene` (a consenting person into footage you own; written consent required).
- **New skills get routed automatically:** `skill-route-sync` reads every installed skill (yours, `npx skills`,
  plugins) and keeps an auto section at the bottom of `~/.claude/skill-router.md` current, with a guessed category
  marked "auto, review" until you confirm it. Your hand-written rows are never touched. Runs on install, on
  `lead update`, daily (if you say yes) and after `skill-add <owner/repo>`. [docs/skill-routing.md](docs/skill-routing.md)
- **skill-recommender mod:** on a tough task, or when a task fails twice, Claude asks you once: "Switch to `<skill>`?".
  Local keyword match, no API, quiet on short replies, logs answers (`recommend.js stats`). Graded by an independent
  reviewer on 54 prompts: 86% of suggestions sensible, 0 fires on 20 short replies; it misses some fits rather than
  guess. `mods/install.sh skill-recommender`
- **Third-party skills linked** in SKILLS.md, with license and install line: Apple's Xcode 27 guidance (7), App Store
  review audits (31), REA (reverse-engineer-anything), hyperframes, huashu-design, openai/skills (15). Licenses for
  remotion, vercel-labs and anthropics entries checked.
- [docs/toolbelt.md](docs/toolbelt.md): MCP servers vs CLIs, MCP config that holds a path not a key, `${VAR}` headers,
  tool output as data, capped `claude -p` runs.

### Changed
- `terminal-lead` and `project-tab`: newer rules (priority lines, check automations' output, queue when the machine is
  overloaded, machine hygiene: no killing processes by name, heavy jobs through `heavy`).
- SKILLS.md sections say which model leads each kind of work; the router template lists the new skills.

**Run this:** `lead update` (then `mods/install.sh skill-recommender` if you want the recommender)

## v0.3.3 (2026-10-14)
### Fixed
- `claude-tab -a <account>` now refuses an account that doesn't exist before opening anything (it used to open a
  window that closed by itself).

### Changed
- Many more tests: account name checks, live sharing, private files never linked, the picker; for the bridge,
  unicode and very long messages, two sends at once, clear errors when the server can't be reached, MCP error
  handling, and hostile-archive checks for the Windows client.

**Run this:** `lead update`

## v0.3.2 (2026-10-14)
### Fixed
- **Typing after a copy no longer opens tmux prompts.** After drag-copying, the pane stayed in scroll mode, so a
  `g` opened tmux's "goto line" prompt (and `f`/`t`/`r` did similar things). Now any ordinary key just leaves scroll
  mode; arrows, PgUp/PgDn and the mouse wheel still scroll, `q` still leaves.

**Run this:** `lead update`

## v0.3.1 (2026-10-14)
### Fixed
- After the one-line setup, the "next steps" now tell you to run `. ~/.profile` (or log in again) when it just put
  `~/.local/bin` on your PATH; before, `claude` and `lead` weren't found in that same shell.
- `mac-tab` calls `tab-view` by its full path (a plain ssh command doesn't load your profile).
- Docs now match the scripts everywhere: full tool table, install steps, broken links and a broken table cell fixed.

**Run this:** `lead update`

## v0.3.0 (2026-10-13)
### Added
- **The bridge** ([docs/bridge.md](docs/bridge.md)): Claude Code on your own Windows / Mac / Linux computer can message
  the lead on your server (`bridge send`), get replies (`bridge inbox`), and keep a shared context folder in sync
  (`bridge sync`), over SSH only. Comes with an MCP server so your local Claude can do it itself, a deny-list so
  secrets never sync, size caps, and an optional locked-down key (`--harden`). Messages and synced files reach a
  Claude session that has a full shell, so treat them as untrusted input; the docs explain.

### Fixed
- `get.sh` no longer fails when the kit's folder isn't on a branch; CI runs on pushes to main.

**Run this:** `lead update`, then on your own computer: `sh mods/bridge/bridge setup me@my-server`
(Windows: `powershell -ExecutionPolicy Bypass -File mods\bridge\bridge.ps1 setup me@my-server`)

## v0.2.0 (2026-10-13)
### Added
- **Separate Claude accounts** (`claude-acct`): personal / work accounts side by side with their own logins, your
  skills and settings shared, `claude-tab -a <account>` for a tab on a chosen account, and each account's 5-hour /
  weekly usage in a picker ([docs/accounts.md](docs/accounts.md)).
- **Update notes**: this changelog, tagged releases, and `lead update` now prints what's new.

**Run this:** `lead update`

## v0.1.0 (2026-10-13)
First public release. Everything below landed on the same day.

### Added
- **Easy setup:** one line on a fresh Ubuntu/Debian server
  (`curl -fsSL https://raw.githubusercontent.com/AlphaSaleAidan/pierce-skill-kit/main/get.sh | bash`), with
  `--dry-run`, `--yes` and `--vps` (server hardening that asks per step and won't turn off password logins unless
  your key login is confirmed). Also a cloud-init snippet and a devcontainer.
- **`lead update`** (pull, re-apply, reload tmux live; `--auto-on` for daily) and **`lead doctor`** (checks the setup
  and prints a fix for each problem).
- **Usage bars** in the kit statusline: 5-hour and weekly plan usage, from Claude Code's own status-line data.
- **Claude Code mods:** agent-board, model-map, projects-hub, statusline, the lead-guard / review-gate /
  mail-no-links hooks, and `mods/extras.sh` for everything else we run (official plugins, Ponytail, MCP servers,
  Jumping Rope, the usage MCP, Ruflo + a small overlay).
- **18 more skills** (video and 3D production, QA and grading, web, decks), indexed in [SKILLS.md](SKILLS.md).
- **Guides:** Windows, macOS, security (with rate-limit recipes and SOC 2 readiness), prompting, memory and context,
  model routing (including what to do when a model refuses), loops, API stack.
- README: 3D hero rendered in Blender by Claude, install-test badge (runs on every push), architecture diagram.

### Fixed
- **Copying in tmux no longer jumps** to the bottom; tmux's bright green borders and selection are now quiet grey.
  On Windows Terminal, Shift+drag uses the terminal's own selection.
- The installers refuse to write into a Claude config folder outside your home folder (a test run with a temporary
  home could otherwise write into a real config).
- `project-tab` skill frontmatter now parses with strict YAML.

**Run this** (installed before `lead update` existed; once):
`cd ~/pierce-skill-kit && git pull && sh install.sh --update && tmux source-file ~/.tmux.conf` and then from now on
just `lead update`.
