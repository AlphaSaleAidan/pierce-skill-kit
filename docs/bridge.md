# Bridge: your own computer's Claude Code, talking to the lead on your server

The bridge lets a Claude Code session on your laptop (Windows, Mac or Linux) message the lead session on your
server, read its answers, and share a folder of context with it: briefs, the decisions log, the reports log, a
memory index, `ROPE.md`. Everything goes over SSH with a key. No open ports, no relay service in the middle.

```
laptop                                            server (the kit, lead in tmux "hub:Lead")
  bridge send "..."   ── ssh ──>  bridge-serve  ──> typed into the lead: [BRIDGE from my-laptop] ...
  bridge inbox        <── ssh ──  outbox        <── the lead runs: bridge reply "..."
  ~/pierce-bridge/context  <── ssh (tar) ──>  ~/.pierce-skill-kit/shared
```

Files: [`mods/bridge/`](../mods/bridge/): `bridge` (Mac/Linux CLI, and on the server `bridge-serve`), `bridge.ps1`
(Windows CLI), `mcp.mjs` (the MCP server for your local Claude Code), `test/e2e.sh`.

## Setup
You need: the kit running on the server, an SSH key that already logs you in (`ssh me@my-server` with no password
prompt; see [windows.md](windows.md) step 1), Node 18+ on the laptop for the MCP server, and Claude Code.

Get the repo on your laptop first: `git clone https://github.com/AlphaSaleAidan/pierce-skill-kit && cd pierce-skill-kit`
(no git on Windows? download https://github.com/AlphaSaleAidan/pierce-skill-kit/archive/refs/heads/main.zip, unzip it,
and open PowerShell in that folder).

**Mac / Linux** (from a clone of this repo):
```sh
sh mods/bridge/bridge setup me@my-server --name my-laptop
export PATH="$HOME/pierce-bridge/bin:$PATH"     # add to ~/.zshrc or ~/.bashrc
```

**Windows** (PowerShell 5.1 or 7, built-in OpenSSH; from a clone of this repo):
```powershell
powershell -ExecutionPolicy Bypass -File mods\bridge\bridge.ps1 setup me@my-server -Name my-laptop
# then add the shortcut it prints to your profile (notepad $PROFILE):
function bridge { & "$HOME\pierce-bridge\bin\bridge.ps1" @args }
```

Setup checks the key login, copies `bridge-serve` (and `bridge`, for `bridge reply`) to `~/.local/bin` on the
server, writes `~/pierce-bridge/config`, and runs
`claude mcp add -s user bridge -- node ~/pierce-bridge/bin/mcp.mjs` (it prints that line instead if `claude` or
`node` isn't found). Restart Claude Code afterwards. Re-running setup is safe.

Add `--harden` (Windows: `-Harden`) to lock the bridge down: see [Security](#security).
A non-standard SSH port or user: put a `Host` entry in `~/.ssh/config` and pass that name to setup.

## Commands
On the laptop:

| Command | What it does |
|---|---|
| `bridge send "<text>"` | types `[BRIDGE from my-laptop] <text>` into the lead window (same lock as `report`), logs it |
| `bridge inbox [--all]` | fetches the lead's replies into `~/pierce-bridge/inbox.txt`, shows the new ones, marks them read |
| `bridge sync` | mirrors the context folder both ways (see below) |
| `bridge sync --watch [N]` | syncs every N seconds (default 60) until Ctrl+C. It polls; there is no file watcher |
| `bridge share <path> < file` | writes one file into the context folder, then syncs |
| `bridge pull [path]` | syncs, then lists the folder (or prints one file) |
| `bridge files` | lists what sync would send, after the deny-list and size caps |

On the server (the lead runs these): `bridge reply "<text>"` (queues an answer for every laptop's inbox) and
`bridge log [N]` (the last N bridge actions).

## MCP tools (local Claude Code)
| Tool | Arguments | Does |
|---|---|---|
| `send_to_lead` | `text` | `bridge send` |
| `read_inbox` | `all` (optional) | `bridge inbox` |
| `share_context` | `path`, `content` | `bridge share`: write a file into the shared folder and sync it |
| `pull_context` | `path` (optional) | `bridge pull`: sync, then list the folder or return one file |

`mcp.mjs` has no dependencies. It speaks MCP over stdio and supports both the `initialize` handshake (revisions
2025-11-25 back to 2024-11-05) and the stateless 2026-07-28 revision (`server/discover`, per-request `_meta`).

## Shared context
| Side | Folder |
|---|---|
| laptop | `~/pierce-bridge/context` (Windows: `%USERPROFILE%\pierce-bridge\context`) |
| server | `~/.pierce-skill-kit/shared` (set `BRIDGE_SHARED` in the kit config to move it) |

A suggested layout: `briefs/`, `decisions.md`, `MEMORY.md` (memory index), `ROPE.md`. On each sync the server also
copies the kit's `reports.tsv` into the folder, so the laptop always has the reports log.

How sync works: the laptop sends its files (tar over ssh), the server merges against what that laptop saw last
time and sends the merged folder back. Changed on one side: that side wins. Deleted on one side and untouched on
the other: deleted on both. **Changed on both sides: both are kept**: the server's version keeps the name, yours
becomes `name.conflict-<laptop-name>-<UTC time>`, and the conflict is printed and logged. One path (tar) on every
OS, so the deny-list is enforced in one place per side; rsync isn't used.

## What never syncs
Matched against every part of the path, case-insensitive, on **both** sides (the laptop never sends them, the
server drops them from anything it receives and never sends them):

`.env*` · `*.pem` · `*.key` · `id_*` · `*secret*` (covers `.secrets/`) · `*.p12` · `*.pfx` · `.ssh/` ·
`*credential*` (covers `.git-credentials`) · `*token*` · `.git/` · `.netrc` · `.npmrc` · `.pypirc` · `.pgpass` ·
`.aws/` · `.docker/` · `kubeconfig*` · `*.kdbx` · `*.ppk` · `*.gpg` · `*.asc` · `.htpasswd`

**Only names are checked, never file contents.** A key pasted into `notes.md` will sync. Keep secrets out of the
folder.

Also: files over **1 MB** are skipped with a note, and a sync over **50 MB** total is refused. Links and special
files never sync. Both sides refuse an archive before unpacking anything if it is compressed (gzip/xz/bzip2...),
lists a file over 1 MB or more than 50 MB in total, has over 5000 entries, or holds a link, an absolute path, `..`,
`\` or `:`. Neither side writes through a folder that is a link: such a file is saved at the top of the folder as
`blocked-...` with a note. Files that don't sync are left alone where they are (never deleted by a sync).
Everything the bridge writes is owner-only (`umask 077`) on Mac/Linux and the server.

## Security
- SSH key only: every call uses `-o BatchMode=yes` (never a password prompt). New server host keys are accepted
  on first use (`StrictHostKeyChecking=accept-new`); a changed host key fails.
- Everything the server does for the bridge is logged to `~/.pierce-skill-kit/bridge.log` (time, client IP,
  action), messages to `~/.pierce-skill-kit/bridge/messages.tsv`.
- **Without `--harden` the bridge uses your normal SSH login**, so a stolen laptop or key gets your full shell
  on the server, bridge or not.
- **Recommended: `setup --harden`.** It makes a new key just for the bridge (`~/pierce-bridge/bridge_key`), shows
  you the exact line, and only after you say `y` adds it to the server's `~/.ssh/authorized_keys`:
  ```
  command="~/.local/bin/bridge-serve",restrict ssh-ed25519 AAAA... pierce-bridge-my-laptop
  ```
  With that key, the server runs `bridge-serve` whatever is asked: only `send`, `fetch`, `sync` and `ping` are
  allowed (names and counts checked, the deny-list re-applied); a shell, any other command, `;`/`&&` tricks and
  port forwarding are refused and logged. Your normal key keeps working for your own logins. If the laptop is
  lost, delete that one line on the server.
- **What the forced command does not stop:** messages and synced files still reach the lead, a Claude session
  with a full shell. Someone holding the bridge key can't run commands, but can try to talk the lead into
  running them (prompt injection). Treat every bridge message and synced file as untrusted input: the lead should
  check with you before acting on anything risky, and the rules sheet still applies.
- Messages are one line, control characters stripped, 8 KB max, before they are typed into the lead. If the lead
  window is a bare shell prompt (Claude has exited), nothing is typed: the message is kept in
  `~/.pierce-skill-kit/bridge/messages.tsv` and the sender is told. Replies are stripped of terminal escape codes
  before the laptop prints them.

## Uninstall
Laptop: `claude mcp remove -s user bridge`, then delete `~/pierce-bridge` (copy out `context/` first if you want it).
Server: `rm ~/.local/bin/bridge-serve ~/.local/bin/bridge`, delete the `command="~/.local/bin/bridge-serve"` line
from `~/.ssh/authorized_keys`, and optionally `~/.pierce-skill-kit/shared`, `~/.pierce-skill-kit/bridge`,
`~/.pierce-skill-kit/bridge.log`.

## Tested vs untested
`sh mods/bridge/test/e2e.sh` runs it all in throwaway containers (a server with sshd + tmux + the kit running
`lead -d` with a stand-in for Claude, a Linux laptop, and PowerShell 7 on Linux): setup, send landing in the lead
pane, reply reaching the inbox, sync both ways, conflicts keeping both, deletes, every deny-list pattern in both
directions plus hand-made archives sent straight to the server (gzip/xz/bzip2, oversize, sparse, 5001 entries,
links, `../`), linked folders on both sides, a bare-shell lead window, escape codes in replies, file modes,
both size caps, the forced command refusing
shells and other commands, the MCP server's handshake, `tools/list` and `tools/call`, and `bridge.ps1`
setup/send/inbox/sync/harden.

**Not tested yet:** `bridge.ps1` receiving a hostile archive (its checks mirror the tested sh ones), a real Windows PC (Windows PowerShell 5.1, `tar.exe`, CRLF checkouts, non-ASCII file names),
macOS (BSD `tar`, `shasum`), and the MCP server inside a real Claude Code session.
