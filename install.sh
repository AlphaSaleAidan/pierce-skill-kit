#!/bin/sh
# Pierce Skill Kit installer. Safe to re-run: it backs up anything it would overwrite and never edits a file twice.
#   ./install.sh            ask before each optional step
#   ./install.sh --yes      do every optional step (all skills, tmux, rules, watchdog, macOS helpers, auto-update, mods, extras)
#   ./install.sh --no       core only: tools, skills, config
#   ./install.sh --defaults everything except the macOS helpers, the extras and auto-update (what get.sh uses)
#   ./install.sh --update   refresh what is already installed, no questions (what `lead update` runs)
set -e
cd "$(dirname "$0")"
# Guard: a CLAUDE_CONFIG_DIR outside this HOME (e.g. a test run with a temp HOME) would write into someone else's
# live Claude config. Refuse unless asked for explicitly.
case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in "$HOME"/*) ;; *)
  [ "$LK_ALLOW_CONFIG_DIR" = 1 ] || { echo "refusing: CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR is outside HOME=$HOME. Unset it (env -u CLAUDE_CONFIG_DIR ...) or set LK_ALLOW_CONFIG_DIR=1 if you mean it." >&2; exit 1; };;
esac
mode=ask; case $1 in --yes) mode=yes;; --no) mode=no;; --defaults) mode=defaults;; --update) mode=update;; "") ;; *) sed -n 2,7p "$0"; exit 2;; esac
BIN=$HOME/.local/bin; CFG=$HOME/.config/pierce-skill-kit; CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
ask() { [ "$mode" = yes ] && return 0; [ "$mode" = no ] || [ "$mode" = update ] && return 1
  if [ "$mode" = defaults ]; then case $1 in *macOS*|*"everything else"*|*automatically*) return 1;; *) return 0;; esac; fi
  printf '%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
put() { # put <src> <dst>: copy, keeping a .bak of a different existing file
  [ -f "$2" ] && ! cmp -s "$1" "$2" && cp "$2" "$2.bak"
  cp "$1" "$2"; }

for d in tmux flock; do command -v $d >/dev/null || { echo "missing: $d (install it first)"; exit 1; }; done
command -v claude >/dev/null || echo "note: 'claude' not on PATH yet - install Claude Code, or set LK_CLAUDE in $CFG/config"

mkdir -p "$BIN" "$CFG" "$CLAUDE_DIR/skills"
for f in bin/*; do if [ -f "$f" ]; then put "$f" "$BIN/$(basename "$f")"; fi; done
chmod +x "$BIN"/claude-acct "$BIN"/lk-doctor "$BIN"/lead "$BIN"/tab-view "$BIN"/claude-tab "$BIN"/brief-send "$BIN"/report "$BIN"/order "$BIN"/heavy "$BIN"/tab-watch "$BIN"/lead-daily
echo "tools  -> $BIN"
skill() { # skill <name>: copy a whole skill folder; an existing different copy is kept as <name>.bak
  d="$CLAUDE_DIR/skills/$1"
  if [ -d "$d" ] && ! diff -rq "skills/$1" "$d" >/dev/null 2>&1; then rm -rf "$d.bak"; mv "$d" "$d.bak"; fi
  mkdir -p "$d" && cp -r "skills/$1/." "$d/"; }
skill terminal-lead; skill project-tab
echo "skills -> $CLAUDE_DIR/skills (terminal-lead, project-tab)"
[ -f "$CFG/config" ] || cp config.example "$CFG/config"
put tmux/pierce-skill-kit.tmux.conf "$CFG/pierce-skill-kit.tmux.conf"
mkdir -p "$CFG/hooks"; put hooks/lead-no-worker-agents.sh "$CFG/hooks/lead-no-worker-agents.sh"; chmod +x "$CFG/hooks/lead-no-worker-agents.sh"
echo "config -> $CFG/config"
pwd > "$CFG/kit-dir"   # where `lead update` pulls from

if [ "$mode" = update ]; then   # refresh only what is already installed
  for d in "$CLAUDE_DIR"/skills/*/; do n=$(basename "$d"); [ -d "skills/$n" ] && skill "$n"; done
  for d in "$CFG"/mods/*/; do n=$(basename "$d"); [ -d "mods/$n" ] && { rm -rf "$d"; cp -r "mods/$n" "$CFG/mods/$n"; }; done
  for f in "$CFG"/hooks/*.sh; do [ -f "hooks/$(basename "$f")" ] && put "hooks/$(basename "$f")" "$f"; done
  echo "update -> refreshed installed skills, mods and hooks"
  exit 0
fi

if ask "Install the other $(($(ls -d skills/*/ | wc -l) - 2)) skills (video/3D production, QA and grading, decks, web; see SKILLS.md)?"; then
  for s in skills/*/; do n=$(basename "$s"); case $n in terminal-lead|project-tab) ;; *) skill "$n";; esac; done
  echo "skills -> all of skills/ (index: SKILLS.md)"
fi
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
if command -v crontab >/dev/null && ask "Update the kit automatically every day (runs lead update at 05:00)?"; then
  (crontab -l 2>/dev/null | grep -v 'pierce-skill-kit auto-update'; echo "0 5 * * * $BIN/lead update --quiet >/dev/null 2>&1 # pierce-skill-kit auto-update") | crontab -
  echo "cron   -> daily auto-update"
fi
if ! command -v jq >/dev/null; then echo "mods   -> skipped: needs jq (then: mods/install.sh <name>)"
elif ask "Install the Claude Code mods (agent-board, model-map, projects-hub, statusline)? Hooks: see mods/README.md"; then
  for m in agent-board model-map projects-hub statusline; do sh mods/install.sh "$m" | sed 's/^/mods   -> /'; done
fi
if ask "Install everything else this setup runs (plugins, Ponytail, MCP servers, Jumping Rope, usage MCP, Ruflo)? It asks per group"; then
  if [ "$mode" = yes ]; then sh mods/extras.sh --yes; else sh mods/extras.sh; fi
fi
case ":$PATH:" in *":$BIN:"*) ;; *) echo "add to your shell profile: export PATH=\"$BIN:\$PATH\"";; esac
echo "done. Start the lead with:  lead     (on Windows: see docs/windows.md)"
