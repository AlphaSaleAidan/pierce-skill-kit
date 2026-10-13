#!/bin/sh
# Pierce Skill Kit installer. Safe to re-run: it backs up anything it would overwrite and never edits a file twice.
#   ./install.sh            ask before each optional step
#   ./install.sh --yes      do every optional step (rules into CLAUDE.md, tmux config, watchdog cron, macOS helpers)
#   ./install.sh --no       core only: tools, skills, config
set -e
cd "$(dirname "$0")"
mode=ask; case $1 in --yes) mode=yes;; --no) mode=no;; "") ;; *) sed -n 2,5p "$0"; exit 2;; esac
BIN=$HOME/.local/bin; CFG=$HOME/.config/pierce-skill-kit; CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
ask() { [ "$mode" = yes ] && return 0; [ "$mode" = no ] && return 1; printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
put() { # put <src> <dst>: copy, keeping a .bak of a different existing file
  [ -f "$2" ] && ! cmp -s "$1" "$2" && cp "$2" "$2.bak"
  cp "$1" "$2"; }

for d in tmux flock; do command -v $d >/dev/null || { echo "missing: $d (install it first)"; exit 1; }; done
command -v claude >/dev/null || echo "note: 'claude' not on PATH yet - install Claude Code, or set LK_CLAUDE in $CFG/config"

mkdir -p "$BIN" "$CFG" "$CLAUDE_DIR/skills"
for f in bin/*; do if [ -f "$f" ]; then put "$f" "$BIN/$(basename "$f")"; fi; done
chmod +x "$BIN"/lead "$BIN"/tab-view "$BIN"/claude-tab "$BIN"/brief-send "$BIN"/report "$BIN"/order "$BIN"/heavy "$BIN"/tab-watch "$BIN"/lead-daily
echo "tools  -> $BIN"
for s in skills/*/; do n=$(basename "$s"); mkdir -p "$CLAUDE_DIR/skills/$n"; put "$s/SKILL.md" "$CLAUDE_DIR/skills/$n/SKILL.md"; done
echo "skills -> $CLAUDE_DIR/skills (terminal-lead, project-tab)"
[ -f "$CFG/config" ] || cp config.example "$CFG/config"
put tmux/pierce-skill-kit.tmux.conf "$CFG/pierce-skill-kit.tmux.conf"
mkdir -p "$CFG/hooks"; put hooks/lead-no-worker-agents.sh "$CFG/hooks/lead-no-worker-agents.sh"; chmod +x "$CFG/hooks/lead-no-worker-agents.sh"
echo "config -> $CFG/config"

if ask "Use the Pierce Skill Kit tmux settings (mouse scroll/copy, LEADER marker)?"; then
  grep -qs 'pierce-skill-kit.tmux.conf' "$HOME/.tmux.conf" || echo "source-file $CFG/pierce-skill-kit.tmux.conf" >> "$HOME/.tmux.conf"
  echo "tmux   -> ~/.tmux.conf sources it"
fi
if ask "Append the rules sheet to $CLAUDE_DIR/CLAUDE.md (every session reads it)?"; then
  if grep -qs 'BEGIN pierce-skill-kit rules' "$CLAUDE_DIR/CLAUDE.md"; then echo "rules  -> already there"
  else { echo; cat templates/CLAUDE.md; } >> "$CLAUDE_DIR/CLAUDE.md"; echo "rules  -> appended to $CLAUDE_DIR/CLAUDE.md"; fi
fi
if ! command -v crontab >/dev/null; then echo "cron   -> skipped: no crontab here; run tab-watch every 15 min some other way"
elif ask "Add the watchdog (tab-watch every 15 min) to your crontab?"; then
  (crontab -l 2>/dev/null | grep -v 'pierce-skill-kit tab-watch'; echo "*/15 * * * * $BIN/tab-watch >/dev/null 2>&1 # pierce-skill-kit tab-watch") | crontab -
  echo "cron   -> tab-watch every 15 min"
fi
if ask "Install the macOS Terminal.app helpers (only if you drive this box from a Mac)?"; then
  for f in bin/macos/mac-tab bin/macos/mac-close-dead bin/macos/hub-check; do put "$f" "$BIN/$(basename "$f")"; chmod +x "$BIN/$(basename "$f")"; done
  echo "macos  -> mac-tab, mac-close-dead, hub-check (set LK_MAC_SSH + LK_BOX_SSH in the config)"
fi
if ! command -v jq >/dev/null; then echo "mods   -> skipped: needs jq (then: mods/install.sh <name>)"
elif ask "Install the Claude Code mods (agent-board, model-map, projects-hub, statusline)? Hooks: see mods/README.md"; then
  for m in agent-board model-map projects-hub statusline; do sh mods/install.sh "$m" | sed 's/^/mods   -> /'; done
fi
case ":$PATH:" in *":$BIN:"*) ;; *) echo "add to your shell profile: export PATH=\"$BIN:\$PATH\"";; esac
echo "done. Start the lead with:  lead"
