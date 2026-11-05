#!/bin/sh
# Plan usage in one command: the usage status line (5h + weekly bars for every account you use, ∞ for no 5-hour
# limit, budgets if you keep them, a server-busy line). It reads only the numbers each account's status line saved:
# no login tokens, no private usage API.
#   sh mods/usage/install.sh               install
#   sh mods/usage/install.sh --uninstall   remove the status line
# Config (kit config file): LK_USAGE_NO_5H (account names with no 5-hour limit, e.g. "main work"). Needs jq.
set -e
cd "$(dirname "$0")"
DEST=$HOME/.config/pierce-skill-kit/mods/statusline
if [ "${1:-}" = --uninstall ]; then sh ../install.sh statusline --uninstall; echo "removed usage mod"; exit 0; fi
sh ../install.sh statusline
cp ../agent-board/bin/health.sh "$DEST/health.sh"   # server-busy line even without the agent-board mod
echo "installed usage mod: the usage status line. Restart Claude Code."
