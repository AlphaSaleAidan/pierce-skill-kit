#!/bin/sh
# Route mod: claude-pick (start Claude on the least-used account, from status-line usage) + task -> skill routing.
#   sh mods/route/install.sh               link claude-pick into ~/.local/bin, copy the skill-router template if you
#                                          have none, then sync the router with your installed skills
#   sh mods/route/install.sh --uninstall   remove the claude-pick link (your router file stays)
# Needs jq. Usage numbers need the statusline (or usage) mod. claude-acct and skill-route-sync come with the kit.
set -e
cd "$(dirname "$0")"; KIT=$(cd ../.. && pwd); BIN=$HOME/.local/bin; D=$HOME/.config/pierce-skill-kit/mods/route
ROUTER=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skill-router.md
if [ "$1" = --uninstall ]; then [ -L "$BIN/claude-pick" ] && rm -f "$BIN/claude-pick"; rm -rf "$D"; echo "removed claude-pick (router kept: $ROUTER)"; exit 0; fi
command -v jq >/dev/null || { echo "needs jq"; exit 1; }
mkdir -p "$BIN" "$D" "$(dirname "$ROUTER")"; cp claude-pick "$D/claude-pick"
ln -sf "$D/claude-pick" "$BIN/claude-pick"
[ -f "$ROUTER" ] || { cp "$KIT/templates/skill-router.md" "$ROUTER"; echo "router template -> $ROUTER (edit it)"; }
"$KIT/bin/skill-route-sync" --quiet >/dev/null 2>&1 || echo "  skill-route-sync did not run; run it yourself: $KIT/bin/skill-route-sync"
echo "installed claude-pick -> $BIN (try: claude-pick). Usage numbers show once each account has drawn the status line."
