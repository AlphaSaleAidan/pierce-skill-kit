#!/bin/sh
# The usage status line in one command. This is the statusline mod (`mods/install.sh statusline`, same files, same
# settings entry) plus the server-busy helper it needs when agent-board isn't installed; there is one status line,
# not two. It shows 5h + weekly bars per account you use, budgets if you keep them and a server-busy line, from the
# numbers each account's status line saved: no login tokens, no private usage API.
#   sh mods/usage/install.sh               install
#   sh mods/usage/install.sh --uninstall   remove the status line
# Config (kit config file, read as text): LK_USAGE_NO_5H="main work" = accounts with no 5-hour limit (shown as ∞).
# Needs jq.
set -e
cd "$(dirname "$0")"
DEST=$HOME/.config/pierce-skill-kit/mods/statusline
if [ "${1:-}" = --uninstall ]; then sh ../install.sh statusline --uninstall; echo "removed usage mod"; exit 0; fi
sh ../install.sh statusline
cp ../agent-board/bin/health.sh "$DEST/health.sh"   # server-busy line even without the agent-board mod
echo "installed usage mod: the usage status line. Restart Claude Code."
