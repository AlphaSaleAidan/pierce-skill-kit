# Windows

The lead and the tabs run on your Linux server (a VPS). Windows is just the window into it: Windows Terminal
and the OpenSSH client that ship with Windows 11 are all you need.

## 1. Connect once, then never type a password again
In PowerShell, one line (replace `me@my-server`):
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/AlphaSaleAidan/pierce-skill-kit/main/bin/windows/ssh-setup.ps1))) me@my-server
```
It asks for your server password once. After that:
- `ssh box` logs in with no password
- `lead` opens the lead, `tab <name>` opens one project tab (new terminals; they're in your PowerShell profile)

Safe to run again. Options: `-Port 2222`, `-Name work` (instead of `box`), `-NoShortcuts`.
If scripts are blocked: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## 2. A Windows Terminal profile (optional)
Settings → Add a new profile named **Lead**, command line `ssh -t box "~/.local/bin/lead"`.

## 3. One Windows Terminal tab per project
[`bin/windows/win-tab.ps1`](../bin/windows/win-tab.ps1) opens hub tabs as Windows Terminal tabs, each an
independent view (switching in one doesn't move the others):
```powershell
setx LK_VPS "me@my-server"          # once, then open a new terminal
.\win-tab.ps1 acme-app data-sync     # those tabs
.\win-tab.ps1 -All                   # every tab in the hub
```
If scripts are blocked: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## What replaces the macOS-only parts
| macOS | Windows |
|---|---|
| `mac-tab` (a Terminal.app tab per project) | `win-tab.ps1` (Windows Terminal tabs) |
| `pbcopy` over a reverse tunnel | nothing to set up: the kit's tmux config turns on OSC 52 (`set -s set-clipboard on`), and Windows Terminal copies a tmux selection to your clipboard |
| Voice Control / dictation | Windows voice typing: **Win+H** in any prompt |
| Selecting text | drag with the mouse to copy (tmux, via OSC 52); the view stays put. **Shift+drag** uses Windows Terminal's own selection instead (bypasses tmux), then **Ctrl+Shift+C** to copy. Scroll back down or just type to leave scroll mode (not **Esc**: once scroll mode has ended, Esc stops Claude) |
| `mac-close-dead`, `hub-check` | not needed: closing a Windows Terminal tab ends its view; the hub tab keeps running on the server |

## Local instead of a server (optional)
WSL2 (`wsl --install`) runs the kit on your PC with the same steps as Linux. A server is still the better
home: tabs keep working when your PC sleeps.

## Tested
Tested on Linux: tmux runs with `set-clipboard on` (from `tmux/pierce-skill-kit.tmux.conf`), `tab-view` gives
independent views, and `win-tab.ps1` parses in PowerShell 7. **Not tested on a real Windows PC yet:** the `wt`
calls, the profile setup and clipboard copy in Windows Terminal.
