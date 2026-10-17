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

## Connect once, then never type a password again
In Terminal (replace `me@my-server`):
```sh
curl -fsSL https://raw.githubusercontent.com/AlphaSaleAidan/pierce-skill-kit/main/bin/ssh-setup | sh -s -- me@my-server
```
It asks for your server password once. After that `ssh box` needs no password, and in a new terminal `lead`
opens the lead and `tab <name>` opens one project tab. Safe to run again. Options: `-p 2222`, `-n work`.

## Scrolling and copying on a Mac
Scroll with the wheel or trackpad; scroll back down (or just type) to get back to the prompt. Don't press
**Esc** to leave scrolling: if scrolling already ended, Esc goes to Claude and stops what it's doing.

Drag to select copies the text. Whether it reaches your Mac's clipboard depends on the app:
- **iTerm2** (recommended): turn on Settings → General → Selection → *Applications in terminal may access
  clipboard* once. Then drag copies, ⌘V pastes. Hold ⌥ while dragging for iTerm's own selection.
- **Terminal.app** can't take a copy from a server's tmux. Press **⌘R** (View → Allow Mouse Reporting) to hand
  the mouse to Terminal, select and ⌘C as usual, then ⌘R again to scroll in tmux. Or use iTerm2.
- If tmux runs **on the Mac itself**, dragging copies straight to the clipboard in both apps.

The selection stays highlighted (dark blue) until you click or type. If it's **yellow**, your tmux started
before the kit's settings were installed: run `lead` again (it loads them), or `tmux source-file ~/.tmux.conf`.

Everything else (lead, claude-tab, report, tab-watch, heavy) is plain POSIX sh + tmux + `flock`
(util-linux); `heavy`'s RAM guard and `tab-watch`'s date maths assume Linux (`/proc/meminfo`, GNU `date`).
