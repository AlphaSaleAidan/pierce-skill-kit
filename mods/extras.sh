#!/bin/sh
# Install everything else this setup runs, one group at a time (asks before each): public plugins, MCP servers,
# Jumping Rope, the usage MCP, and Ruflo + the kit's overlay. Uses the `claude` CLI; prints the commands if it's missing.
#   mods/extras.sh          ask per group
#   mods/extras.sh --yes    every group
#   mods/extras.sh --list   only print the commands
cd "$(dirname "$0")" || exit 1
case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in "$HOME"/*) ;; *)
  [ "$LK_ALLOW_CONFIG_DIR" = 1 ] || { echo "refusing: CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR is outside HOME=$HOME (set LK_ALLOW_CONFIG_DIR=1 if you mean it)" >&2; exit 1; };;
esac
mode=ask; case $1 in --yes) mode=yes;; --list) mode=list;; "") ;; *) sed -n 2,6p "$0"; exit 2;; esac
command -v claude >/dev/null || { [ "$mode" = list ] || echo "note: 'claude' not on PATH, printing the commands instead"; mode=list; }
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}; KIT=$(cd .. && pwd); fails=0
ask() { [ "$mode" = yes ] && return 0; [ "$mode" = list ] && { echo; echo "# $1"; return 0; }; printf '\n%s [y/N] ' "$1"; read -r a; [ "$a" = y ] || [ "$a" = Y ]; }
run() { echo "+ $*"; [ "$mode" = list ] && return 0; "$@" || { echo "  ! failed: $*"; fails=$((fails + 1)); }; }
mcp() { # mcp <name> <claude mcp add args...>: skip a server that's already configured, so re-runs are safe
  n=$1; shift
  if [ "$mode" != list ] && claude mcp get "$n" >/dev/null 2>&1; then echo "= $n already configured"; else run claude mcp add -s user "$@"; fi; }

if ask "Plugins from the official marketplace (superpowers, hookify, hyperframes, claude-md-management, session-report, security-guidance)?"; then
  run claude plugin marketplace add anthropics/claude-plugins-official   # not added by default on a fresh install
  for p in superpowers hookify hyperframes claude-md-management session-report security-guidance; do run claude plugin install "$p@claude-plugins-official"; done
fi
if ask "Ponytail ('lazy senior dev' mode, MIT, by DietrichGebert)?"; then
  run claude plugin marketplace add DietrichGebert/ponytail
  run claude plugin install ponytail@ponytail
fi
if ask "Service plugins (vercel, stripe, shippo, discord, telegram, vapi-voice-ai, watch): only if you use those services?"; then
  run claude plugin marketplace add anthropics/claude-plugins-official
  for p in vercel stripe shippo discord telegram; do run claude plugin install "$p@claude-plugins-official"; done
  run claude plugin marketplace add VapiAI/skills;              run claude plugin install vapi-voice-ai@vapi-skills
  run claude plugin marketplace add bradautomates/claude-video; run claude plugin install watch@claude-video
fi
if ask "Anthropic's skills marketplace (anthropics/skills; then pick skills with /plugin)?"; then
  run claude plugin marketplace add anthropics/skills
fi
if ask "MCP servers (playwright, context7, memory, sequentialthinking, higgsfield)?"; then
  mcp playwright playwright -- npx -y @playwright/mcp@latest
  mcp context7 context7 -- npx -y @upstash/context7-mcp@latest
  mcp memory memory -- npx -y @modelcontextprotocol/server-memory
  mcp sequentialthinking sequentialthinking -- npx -y mcp-sequentialthinking-tools
  mcp higgsfield --transport http higgsfield https://mcp.higgsfield.ai/mcp   # signs in on first use; generation is paid
  echo "  21st.dev components MCP needs a paid API key: see 21st.dev's docs, then: claude mcp add -s user --transport http 21st https://21st.dev/api/mcp ..."
fi
if ask "Jumping Rope (ROPE.md session log that survives compaction) as a skill?"; then
  [ -d "$HOME/jumping-rope" ] || run git clone -q https://github.com/AlphaSaleAidan/jumping-rope "$HOME/jumping-rope"
  run mkdir -p "$CLAUDE_DIR/skills"
  run cp -r "$HOME/jumping-rope/adapters/claude-skill/jumping-rope" "$CLAUDE_DIR/skills/"
fi
if ask "claude-usage MCP (plan usage in a tool + status line)?"; then
  [ -d "$HOME/claude-usage-mcp" ] || run git clone -q https://github.com/AlphaSaleAidan/claude-usage-mcp "$HOME/claude-usage-mcp"
  mcp claude-usage claude-usage -- node "$HOME/claude-usage-mcp/server.mjs"
fi
if ask "Ruflo (ruvnet, MIT) in your home folder + the kit's overlay (covers every tab without its own init)?"; then
  if [ -f "$HOME/.claude/helpers/hook-handler.cjs" ]; then echo "= ruflo already initialised in $HOME"
  else run sh -c 'cd "$HOME" && npx -y ruflo@latest init --no-global'; fi
  run bash "$KIT/mods/ruflo/apply.sh" "$HOME"
fi
echo; [ "$mode" = list ] || { [ "$fails" = 0 ] && echo "done. Restart Claude Code." || echo "done with $fails failure(s) above."; }
