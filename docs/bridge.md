# Bridge: your own computer's Claude Code, talking to the lead on your server

The bridge lets a Claude Code session on your laptop (Windows, Mac or Linux) message the lead session on your
server, read its answers, and share a folder of context with it: briefs, the decisions log, the reports log, a
memory index, `ROPE.md`. Everything goes over SSH with a key. No open ports, no relay service in the middle.

**Moving big files (PDFs, videos, exports)?** Jump to the [file store](#file-store-big-files-both-ways).

```
laptop                    server
bridge send  ── ssh ──>  typed into the lead
bridge inbox <── ssh ──  bridge reply "..."
context/     <── ssh ──> shared/
PierceFiles/ <── ssh ──> files/
```
On the laptop the folders are `~/pierce-bridge/context` and `~/PierceFiles`; on the server they're
`~/.pierce-skill-kit/shared` and `~/.pierce-skill-kit/files`. The lead runs in tmux (`hub:Lead`).

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
sh mods/bridge/bridge setup me@my-server
# add this line to ~/.zshrc or ~/.bashrc:
export PATH="$HOME/pierce-bridge/bin:$PATH"
```

**Windows** (PowerShell 5.1 or 7, built-in OpenSSH; in the repo folder). Once per PC, let your own scripts run
(Windows blocks them by default, and marks files from a zip download as "from the internet"):
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Get-ChildItem -Recurse | Unblock-File
```
Then:
```powershell
.\mods\bridge\bridge.ps1 setup me@my-server
# then open your profile:  notepad $PROFILE
# and add the shortcut it prints:
function bridge {
  & "$HOME\pierce-bridge\bin\bridge.ps1" @args
}
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
| `bridge sync --list` | lists what sync would send, after the deny-list and size caps |
| `bridge files` / `setup` / `push` / `pull` / `share` | the [file store](#file-store-big-files-both-ways) for big files |

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

## File store (big files, both ways)
A folder on your computer (`~/PierceFiles`; on Windows `C:\Users\<you>\PierceFiles`) and one on the server
(`~/.pierce-skill-kit/files`), linked over the same SSH connection. Files up to **100 MB** each. Nothing else to
install or pay for. On the server, tell Claude: "put the result in ~/.pierce-skill-kit/files".

Set it up once:
```
bridge files setup
```
Send what's new or changed in your folder:
```
bridge files push
```
Send one file from anywhere (it's copied into the folder first):
```
bridge files push ~/Desktop/q3.pdf
```
On Windows, type `bridge files push ` and drag the file from Explorer into the PowerShell window to paste its path
(your Desktop may live under OneDrive, so typing it is easy to get wrong):
```
bridge files push "C:\...\Desktop\q3.pdf"
```
Get what Claude made on the server:
```
bridge files pull
```
See what's the same, what's waiting, and what changed on both sides (nothing is moved):
```
bridge files
```

What it looks like:
```
> bridge files push
  sending clients/q3.md (1 KB)
  sending demo-video.mp4 (7.6 MB)
sent 2 files to the server
> bridge files pull
  got clients/summary.md (26 bytes)
got 1 file from the server, in /home/jake/PierceFiles
```

Good to know:
- **Only new or changed files travel,** in batches of up to 100 MB, each file listed as it goes (no percentage
  bar). If the link drops, run the same command again: finished files aren't sent twice. Allow about a minute per
  100 MB on a typical home upload.
- **Deleting a file doesn't delete it on the other side.** Delete it in both places, or ask Claude to.
- **Changed on both sides?** `push` won't overwrite the server's copy; it tells you to pull. `pull` keeps both: the
  server's copy takes the name and yours moves beside it as `q3.conflict-<your computer>-<time>.md`.
- **Nothing is lost.** When a file is replaced, the old copy goes to `~/pierce-bridge/files-trash/` (your computer)
  or `~/.pierce-skill-kit/bridge/files-trash/` (server). Empty those yourself now and then.
- **Secrets stay home.** Same deny-list as sync: `.env`, keys, `.ssh`, anything named secret, token or credential.
  Push tells you once which files it kept back. Caught one by mistake (a Keynote `.key`, "Secret Santa.xlsx")?
  Rename it, or zip it.
- **Names Windows can't hold** (with `\ : * ? " < > |`, ending in a dot or space, or `CON`, `NUL`...) are skipped
  with a note, on every computer, so the folder always works on Windows too.
- **Server off or computer asleep?** Push and pull say "can't reach the server" and change nothing. Run them
  again later. There's no background sync: you push and pull when you want.
- **The first time:** your server needs the new bridge. Run `bridge setup me@my-server` again (keeps your
  settings). An old server answers "the server has an older bridge" with the exact command.

### Share a file by link (off by default)
```
bridge files share q3.pdf 30
```
pushes `q3.pdf` if needed, then prints a link anyone can open for 30 minutes (default 60, max 1440). Each link has
a random part and serves that one file only. The server owner turns this on with `LK_FILES_SHARE=1` in
`~/.config/pierce-skill-kit/config`, and needs `cloudflared` and `python3` on the server.

## What never syncs (context folder and file store)
Matched against every part of the path, case-insensitive, on **both** sides (the laptop never sends them, the
server drops them from anything it receives and never sends them):

`.env*` · `*.pem` · `*.key` · `id_*` · `*secret*` (covers `.secrets/`) · `*.p12` · `*.pfx` · `.ssh/` ·
`*credential*` (covers `.git-credentials`) · `*token*` · `.git/` · `.netrc` · `.npmrc` · `.pypirc` · `.pgpass` ·
`.aws/` · `.docker/` · `kubeconfig*` · `*.kdbx` · `*.ppk` · `*.gpg` · `*.asc` · `.htpasswd`

**Only names are checked, never file contents.** A key pasted into `notes.md` will sync. Keep secrets out of the
folder.

In the context folder, files over **1 MB** are skipped with a note and a sync over **50 MB** total is refused (the file store allows 100 MB a file). Links and special
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
  With that key, the server runs `bridge-serve` whatever is asked: only `send`, `fetch`, `sync`, `ping` and the `files-*` actions are
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
setup/send/inbox/sync/harden, and the file store from both clients: setup, push, pull, a 5 MB file byte for byte,
replaced copies kept, push of an outside file and of one folder, the deny-list, the 100 MB cap, `files-get` refusing
paths outside the store, sharing off by default then on (a stand-in `cloudflared`), and a clear message when offline.

**Not tested yet:** `bridge.ps1` receiving a hostile archive (its checks mirror the tested sh ones), a real Windows PC (Windows PowerShell 5.1, `tar.exe`, CRLF checkouts, non-ASCII file names),
macOS (BSD `tar`, `shasum`), and the MCP server inside a real Claude Code session.
