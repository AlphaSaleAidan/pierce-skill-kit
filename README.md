<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/hero/hero-dark.png">
    <img alt="A lead node floating above five project-tab nodes, with report beams rising from the tabs to the lead" src="assets/hero/hero-light.png" width="100%">
  </picture>
</p>

<h1 align="center">Pierce Skill Kit</h1>

<p align="center">
  <b>One lead. Many Claude Code tabs. Briefs out, reports in, nothing silently stuck.</b>
</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-0087af?style=flat-square"></a>
  <a href="https://github.com/AlphaSaleAidan/pierce-skill-kit/actions/workflows/test.yml"><img alt="install test" src="https://img.shields.io/github/actions/workflow/status/AlphaSaleAidan/pierce-skill-kit/test.yml?branch=main&label=install%20test&style=flat-square"></a>
  <img alt="tmux + Claude Code" src="https://img.shields.io/badge/runs%20on-tmux%20%2B%20Claude%20Code-30363d?style=flat-square">
  <a href="CHANGELOG.md"><img alt="Updates" src="https://img.shields.io/github/v/release/AlphaSaleAidan/pierce-skill-kit?label=updates&style=flat-square&color=d70000"></a>
</p>

> **Latest (v0.4.2):** the brain-loop mod (Obsidian + Opus + Jev loop: a linked vault, report triage, plan grading, MCP tools) and the `tab-plan` skill. **v0.4.0:** 4 more skills (22 in all), 60+ more third-party skills linked (Apple Xcode 27, App Store review audits, REA…), new skills routed automatically (`skill-route-sync`), and the skill-recommender mod ("Switch to `<skill>`?"). **v0.3.3:** `claude-tab -a` checks the account first. **v0.3.0:** the bridge: Claude Code on your own computer messages the server lead over SSH.
> **v0.2.0:** separate Claude accounts (`claude-acct`); update notes and releases. **v0.1.0:** one-line setup, `lead update` / `lead doctor`, usage bars, copy no longer jumps, mods + 18 skills.
> Already installed? Run `lead update`. All changes: [CHANGELOG.md](CHANGELOG.md).

Run many Claude Code sessions at once without losing track of them. One **lead** session manages a set of
**project tabs** in tmux: it writes briefs, hands them out, gets a report the moment anything finishes or
breaks, and only bubbles up to you what needs you. It comes with a skill for each role, a model-routing tree
that keeps token spend sane, and a one-page [rules sheet](RULES.md) that keeps it safe to leave running.

## From zero in 3 steps
1. **Get a Linux server** (Ubuntu or Debian; 4 GB RAM is plenty) from any host. Optional: paste
   [deploy/cloud-init.yaml](deploy/cloud-init.yaml) into its "user data" box and step 2 happens on first boot.
2. **Paste one line** on the server (it shows the plan first; `--dry-run` to only look, `--vps` to also harden the server):
   ```sh
   curl -fsSL https://raw.githubusercontent.com/AlphaSaleAidan/pierce-skill-kit/main/get.sh | bash
   ```
3. **Sign in and start:** `claude` (once), then `lead`. Check anything with `lead doctor`.
4. **On your own computer** (Mac or Linux), one line sets up password-free login plus `lead` and `tab <name>`
   shortcuts that open them from there (Windows: [docs/windows.md](docs/windows.md)):
   ```sh
   curl -fsSL https://raw.githubusercontent.com/AlphaSaleAidan/pierce-skill-kit/main/bin/ssh-setup | sh -s -- me@my-server
   ```

> **On Windows:** Windows Terminal + ssh, a `lead` shortcut and a tab per project: [docs/windows.md](docs/windows.md).
> **On a Mac:** any terminal + ssh works; optional Terminal.app tab helpers: [docs/macos.md](docs/macos.md).
> **Just trying it?** Open the repo in a devcontainer (VS Code / Codespaces) and it sets itself up.

<table>
<tr>
<td width="50%" valign="top"><img src="assets/icons/tabs.svg" width="28" alt=""><br><b>One lead, many tabs</b><br>Each project gets its own Claude Code tab; the lead routes work and refuses duplicates.</td>
<td width="50%" valign="top"><img src="assets/icons/report.svg" width="28" alt=""><br><b>Reports, one path</b><br><code>report</code> logs every result with proof and types it straight into the lead.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="assets/icons/watch.svg" width="28" alt=""><br><b>Nothing silently stuck</b><br>A watchdog flags idle tabs, but not the ones waiting on you.</td>
<td width="50%" valign="top"><img src="assets/icons/route.svg" width="28" alt=""><br><b>Model routing</b><br>Strongest model for hard calls and grading; cheaper ones for lanes and lookups.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="assets/icons/shield.svg" width="28" alt=""><br><b>Rules that hold</b><br>Ask before sends, prove before done, no prod without you. One page, with the why.</td>
<td width="50%" valign="top"><img src="assets/icons/queue.svg" width="28" alt=""><br><b>Box-friendly</b><br>Heavy jobs queue two at a time, low priority, with a RAM guard.</td>
</tr>
</table>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/architecture-dark.svg">
    <img alt="Architecture: you talk to the lead; the lead sends briefs to project tabs; tabs report back; a watchdog flags idle tabs; heavy jobs queue box-wide" src="assets/architecture-light.svg" width="100%">
  </picture>
</p>

## Updating
`lead update` pulls the latest kit, re-applies it and reloads tmux live; `lead update --auto-on` does it every day.
`lead doctor` checks the setup and prints a fix for anything missing.

## Install
Needs Linux, `tmux`, `flock` (util-linux) and [Claude Code](https://docs.claude.com/en/docs/claude-code).
```sh
git clone https://github.com/AlphaSaleAidan/pierce-skill-kit && cd pierce-skill-kit && ./install.sh
```
It puts the tools in `~/.local/bin`, the two lead/tab skills in `~/.claude/skills`, a config at
`~/.config/pierce-skill-kit/config`, then **asks** before each optional step: the other 23 skills, daily skill routing, the tmux settings,
appending the rules to your `~/.claude/CLAUDE.md`, the watchdog cron, the macOS helpers, the daily auto-update, the
Claude Code mods and the extras. `--yes` (all) / `--no` (none) / `--defaults` (all but the macOS helpers,
auto-update and extras; what `get.sh` uses) skip the questions.

## The workflow
```sh
lead                                      # start (or reattach to) the lead
claude-tab ~/code/acme-app -n acme-app    # open a project tab (refuses duplicates)
brief-send acme-app briefs/1013-acme-app-checkout.md   # hand it a written brief
# ...inside the tab, when something finishes or needs you:
report acme-app done "checkout fixed, e2e green on preview" https://preview.example.com
```
Full example: [examples/walkthrough.md](examples/walkthrough.md).

| Tool | What it does |
|---|---|
| `lead [-d]` | start the lead session (`hub:Lead`) or bring it back in this terminal |
| `lead doctor` / `lead update [--auto-on\|--auto-off]` | check the setup / pull the latest kit and re-apply it |
| `claude-tab <dir> -n <name> [-p task \| -b brief.md] [-r id \| -c] [-m model] [-a account] [-f]` | open a project tab; refuses a duplicate name/folder/session (`-b`: start on a brief, `-c`: pick up the folder's last conversation, `-f`: allow a second tab in a folder) |
| `tab-view <hub:N>` | look at one tab in this terminal without moving anyone else's view |
| `brief-send <tab> <brief.md>` | point a tab at a brief file in one line |
| `report <project> <status> "<line>" [proof]` | the only way a tab tells the lead something; logged + typed into the lead. Status: `done`, `progress`, `blocked`, `needs-human` or `failed`. Each one gets a cheap second look (`report-check`): a `done` without proof, or a claimed deploy/send/merge, is tagged so the lead checks it first |
| `tab-sweep [--dry-run]` | close finished tabs: last report `done`, work committed, nothing still serving, quiet for a while. Flags the ones that aren't; logs how to reopen each |
| `order add\|done\|wait\|list` | ledger of your asks, closed only with proof; shows each one's age, `OLD` past 24 h |
| `lead-round` | one screen for the lead's monitor round: machine, orders, tabs (stuck on a prompt? unsaved?), jobs, heartbeats, tunnels, what `tab-sweep` would close. Red lines start with `!` |
| `lead-recall <words>` | search decisions, briefs, reports, orders and memory before asking the human again |
| `tab-watch` | watchdog: flags tabs idle with no report (not ones waiting on you) |
| `heavy <cmd>` | box-wide queue for CPU-heavy commands |
| `job run <name> -- <cmd>` | run a headless job under a watchdog: relaunched after a crash or a usage-limit reset, every step reported (`job list`, `job stop`) |
| `ssh-setup me@server` | on your own computer: password-free login plus `lead` / `tab <name>` shortcuts ([Mac](docs/macos.md), [Windows](docs/windows.md)) |
| `claude-acct [add\|list\|run]` | separate Claude accounts for separate purposes, shared setup, per-account usage ([docs/accounts.md](docs/accounts.md)) |
| `lead-daily [--summary]` | end-of-day digest of reports, open orders, briefs and decisions |
| `skill-route-sync [--confirm name] [--dry-run]` / `skill-add <owner/repo>` | route every installed skill in your skill router; install skills and route them |

## Skills
Beyond the two lead/tab skills, 23 skills we wrote ourselves, grouped and indexed in [SKILLS.md](SKILLS.md):
quality and grading (video QC, lip-sync/gaze QC, phone-agent QA), video and 3D production (commercial pipeline,
Blender sets from storyboards, green-screen comps, kinetic type, beat-synced overlays, logo fixes, voice conversion
with consent, putting a consenting person into your own footage), design and web (site build), decks and same-day
sales-meeting prep, Codex hand-offs, separate Claude accounts, collaborator sandboxes, and credit discipline for paid generation.
Plus recommended third-party skills (linked, not copied, with license and install line) and a router template:
[templates/skill-router.md](templates/skill-router.md). `skill-route-sync` keeps your router current as you install skills
([docs/skill-routing.md](docs/skill-routing.md)).

## Mods
Claude Code plugins and hooks that go with it, one command each ([mods/README.md](mods/README.md)): **agent-board**
(live subagent board + ask tool + lead relay), **model-map** (remap subagent models live), **projects-hub** (`/hub`:
projects, sessions, PRs, services), **statusline**, **bridge** (Claude Code on your own computer talks to the lead
over SSH: [docs/bridge.md](docs/bridge.md)), **skill-recommender** (asks "Switch to `<skill>`?" when an installed
skill fits a tough task better), **brain-loop** (the loop below), the **lead-guard**, **review-gate** and
**mail-no-links** hooks, and `mods/extras.sh` for everything else (official plugins, Ponytail, MCP servers, Jumping
Rope, the usage MCP, Ruflo + overlay).

## Obsidian + Opus + Jev loop
An optional mod (`mods/brain-loop`) that closes the loop around the lead: **plan → act → observe → improve**.
- **Plan:** the lead writes one plan file per task (`tab-plan` skill): numbered directions, timed checkpoints,
  the owner's decisions. The tab gets only a pointer to it.
- **Act:** Opus runs the lead and the tabs, as before.
- **Observe:** every report is triaged by a small router: does it need the owner, is the tab blocked, is a "done"
  actually proven, does it say what's next, which plan and which order does it belong to. Confident answers are
  written for you (a Progress log line in the plan, the order marked in the brain); unsure ones reach the lead in
  one batched message. `stuck-check` re-raises reports left waiting on the owner and overdue checkpoints.
- **Improve:** at close, `brain-loop grade` scores how well the tab followed each direction; the most-missed ones
  become a rule note.
- **Memory:** everything lands in a vault: an Obsidian-compatible folder with one note per project, person, ask,
  decision, plan and rule, linked both ways. Open asks are sorted by when to chase them. Your own edits (text below
  the marker, `my_*` fields) survive every rebuild. Claude reads it through three MCP tools (`brain`, `brain_open`,
  `brain_mark`), and the lead gets the top 15 open items at the start of every session.
- **Jev** (a small decision model on OpenRouter) is the cheap triage step. It's off until you set a monthly cap.

Setup (needs python3; nothing to pip install):
```sh
mods/install.sh brain-loop                     # the brain-loop command + the SessionStart hook
cp examples/brain-loop-inputs/entities.json ~/.pierce-skill-kit/brain-entities.json   # then list your projects/people
brain-loop build && brain-loop open            # write the vault, show open items
claude mcp add -s user brain -- ~/.local/bin/brain-loop mcp
brain-loop page                                # graph view at http://127.0.0.1:8790/brain/
```
Then cron `brain-loop build`, `brain-loop route run --apply` and `brain-loop stuck` every 15 minutes. Every path is in
the config (`BRAIN_*` in [config.example](config.example)). A small vault built from made-up data is in
[examples/brain-vault](examples/brain-vault). Details: [mods/brain-loop/README.md](mods/brain-loop/README.md).

**Cost:** the rules engine is free and the default. Jev is about $0.00004 per report call (measured); `hybrid`
makes one call per report, plan-grade one per direction plus a headless Sonnet check for the unsure ones.

**How well it works.** These numbers come from one operator's own data, not a benchmark:
- Brain vs plain search: 18/20 questions answered correctly with the vault vs 9/20 with plain text search
  (20 questions; a blind answerer, then a separate strict grader).
- Router (`hybrid`) on 40 held-out reports vs labels made independently: needs the owner 90%, blocked 92%, done and
  proven 90%, right plan 100%, right order rows 85%, says what's next 82%, urgency 55%. Urgency never acts on
  its own.
- Jev alone was weaker (72 / 55 / 88 / 70% on the fields it was scored on), but every answer it gave with 0.9+
  confidence on the 60-report tuning set was right. So `hybrid` lets Jev win a field only when it's that sure,
  and sends disagreements to the lead.
- Plan-grade: Jev was confident on only about 30% of directions; a Sonnet check decides the rest.

## Docs
- [RULES.md](RULES.md): the rules sheet (paste-ready: [templates/CLAUDE.md](templates/CLAUDE.md))
- [docs/model-routing.md](docs/model-routing.md): which model for which job, and why it saves tokens
- [docs/loops.md](docs/loops.md): grading loops and wait loops that don't run away
- [docs/report-protocol.md](docs/report-protocol.md) · [docs/briefs.md](docs/briefs.md) · [docs/skill-routing.md](docs/skill-routing.md)
- [docs/toolbelt.md](docs/toolbelt.md): MCP servers vs CLIs, keys by path, capped headless runs
- [docs/security.md](docs/security.md): agent security, rate-limit recipes (Express, Next.js, nginx), app basics, SOC 2 audit-readiness
- [docs/safety-rules.md](docs/safety-rules.md): what the tools enforce vs what's on Claude, plus the optional lead hook
- [docs/prompting.md](docs/prompting.md): briefs, talking to Claude, graders, subagents, creative prompts, dictation
- [docs/memory-and-context.md](docs/memory-and-context.md): file memory, the index, and keeping context across long sessions
- [docs/api-stack.md](docs/api-stack.md): example services + env var names, and how to store keys by path
- [docs/windows.md](docs/windows.md): Windows Terminal + ssh into your server, a `lead` shortcut, a tab per project
- [docs/bridge.md](docs/bridge.md): let Claude Code on your own computer (Windows/Mac/Linux) message the lead and share context, over SSH only
- [docs/accounts.md](docs/accounts.md): separate Claude accounts (personal / work), per-account tabs and usage
- [docs/macos.md](docs/macos.md): optional Terminal.app helpers (macOS-only)

## What's macOS-specific
Only `bin/macos/` (`mac-tab`, `mac-close-dead`, `hub-check`), which drive Terminal.app over SSH with `osascript`.
Everything else runs on the Linux server; `heavy` reads `/proc/meminfo` and `tab-watch` uses GNU `date`.

## Test
`tests/smoke.sh` installs the kit as a fresh user in a throwaway container, starts a lead, opens two tabs,
sends a report and checks the watchdog flags an idle tab:
```sh
docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/smoke.sh
```
The other suites in `tests/` run the same way (each file's first lines show how), plus `sh mods/bridge/test/e2e.sh`.

## License
MIT
