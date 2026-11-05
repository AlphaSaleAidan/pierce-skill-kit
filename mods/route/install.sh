#!/bin/sh
# Route mod: claude-pick (start Claude on the account with the most room, from status-line usage).
#   sh mods/route/install.sh               link claude-pick into ~/.local/bin
#   sh mods/route/install.sh --uninstall   remove it
# Needs jq. Usage numbers need the usage status line (sh mods/usage/install.sh). claude-acct comes with the kit.
# The task -> skill router is set up by the kit's main install.sh, not here.
set -e
cd "$(dirname "$0")"; BIN=$HOME/.local/bin; D=$HOME/.config/pierce-skill-kit/mods/route
if [ "$1" = --uninstall ]; then [ -L "$BIN/claude-pick" ] && rm -f "$BIN/claude-pick"; rm -rf "$D"; echo "removed claude-pick"; exit 0; fi
command -v jq >/dev/null || { echo "needs jq"; exit 1; }
mkdir -p "$BIN" "$D"; cp claude-pick "$D/claude-pick"
ln -sf "$D/claude-pick" "$BIN/claude-pick"
echo "installed claude-pick -> $BIN (try: claude-pick). Usage numbers show once each account has drawn the status line."
