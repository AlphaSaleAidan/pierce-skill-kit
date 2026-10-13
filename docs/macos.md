# macOS (optional)

The core kit is Linux + tmux and runs anywhere you SSH in from. If you drive the server from **Terminal.app
on a Mac** and want each tab as its own Mac tab, three optional helpers do that (`./install.sh` asks):

| Tool | Does |
|---|---|
| `mac-tab <hub:N> "Name"` | opens that tab as a new Terminal.app tab (via `osascript`) |
| `mac-close-dead` | closes Terminal windows whose server session ended. Closes by window, never by keystroke |
| `hub-check [--fix]` | checks one live Mac window per hub tab; `--fix` closes dead ones by id |

They need two settings in `~/.config/pierce-skill-kit/config`:
- `LK_MAC_SSH`: how the server reaches the Mac. Usually a reverse tunnel you open from the Mac
  (`ssh -R 2222:localhost:22 me@my-server`), then `LK_MAC_SSH='ssh -p 2222 -o BatchMode=yes me@localhost'`.
- `LK_BOX_SSH`: how the Mac reaches the server, e.g. `'ssh -t me@my-server'`.

Real tabs (not windows) need Accessibility permission for `sshd` on the Mac
(System Settings → Privacy & Security → Accessibility). Without it, `mac-tab` opens windows instead.

Clipboard: Terminal.app ignores OSC 52, so the tmux snippet's default copy won't reach it. Use the
commented `pbcopy` line in `tmux/pierce-skill-kit.tmux.conf`, or use iTerm2, which supports OSC 52.

Everything else (lead, claude-tab, report, tab-watch, heavy) is plain POSIX sh + tmux + `flock`
(util-linux); `heavy`'s RAM guard and `tab-watch`'s date maths assume Linux (`/proc/meminfo`, GNU `date`).
