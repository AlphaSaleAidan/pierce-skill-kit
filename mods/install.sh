#!/bin/sh
# Install or remove one Claude Code mod from this kit. Edits your Claude settings.json (a .bak is kept first).
#   mods/install.sh agent-board|model-map|projects-hub     plugin mods (loaded via CLAUDE_CODE_PLUGIN_DIRS)
#   mods/install.sh statusline                             the status line
#   mods/install.sh skill-recommender                      suggests a better-fitting skill on tough tasks (needs Node)
#   mods/install.sh hook lead-guard|review-gate|mail-no-links [matcher]
#   add --uninstall to any of these to remove it.          Restart Claude Code afterwards. Needs jq.
set -e
cd "$(dirname "$0")"
# Guard: a CLAUDE_CONFIG_DIR outside this HOME (e.g. a test run with a temp HOME) would write into someone else's
# live Claude config. Refuse unless asked for explicitly.
case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in "$HOME"/*) ;; *)
  [ "$LK_ALLOW_CONFIG_DIR" = 1 ] || { echo "refusing: CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR is outside HOME=$HOME. Unset it (env -u CLAUDE_CONFIG_DIR ...) or set LK_ALLOW_CONFIG_DIR=1 if you mean it." >&2; exit 1; };;
esac
KIT=$(cd .. && pwd); DEST=$HOME/.config/pierce-skill-kit/mods
SET=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json
command -v jq >/dev/null || { echo "needs jq"; exit 1; }
mkdir -p "$(dirname "$SET")"; [ -f "$SET" ] || echo '{}' > "$SET"
edit() { cp "$SET" "$SET.bak"; jq "$@" "$SET.bak" > "$SET"; }   # edit <jq args...>: rewrite settings.json via jq
what=$1; un=''; for a in "$@"; do [ "$a" = --uninstall ] && un=1; done

case $what in
  agent-board|model-map|projects-hub)
    d=$DEST/$what
    if [ -n "$un" ]; then
      edit --arg d "$d" '.env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(. != $d and . != "")) | join(":"))'
      rm -rf "$d"; echo "removed $what"
    else
      mkdir -p "$DEST"; rm -rf "$d"; cp -r "$what" "$d"
      edit --arg d "$d" '.env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":") | map(select(. != $d and . != "")) + [$d] | join(":"))'
      echo "installed $what -> $d (restart Claude Code)"
    fi;;
  statusline)
    d=$DEST/statusline
    if [ -n "$un" ]; then
      edit --arg d "$d" 'if (.statusLine.command // "" | contains($d)) then del(.statusLine) else . end'; rm -rf "$d"; echo "removed statusline"
    else
      mkdir -p "$DEST"; rm -rf "$d"; cp -r statusline "$d"
      edit --arg c "sh $d/statusline.sh" '.statusLine = {type: "command", command: $c}'
      echo "installed statusline -> $d (git + model + config; hub counts and overload warning if projects-hub / agent-board are installed too)"
    fi;;
  skill-recommender)
    d=$DEST/skill-recommender
    # drop any earlier copy of our three hooks, then (unless uninstalling) add them back
    for ev in UserPromptSubmit PostToolUse PostToolUseFailure; do
      edit --arg d "$d" --arg ev "$ev" '.hooks[$ev] = ((.hooks[$ev] // []) | map(.hooks |= map(select((.command // "") | contains($d) | not))) | map(select((.hooks | length) > 0))) | if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end'
    done
    if [ -n "$un" ]; then rm -rf "$d"; echo "removed skill-recommender (its log stays in ~/.cache/skill-recommender)"; else
      command -v node >/dev/null || { echo "skill-recommender needs Node"; exit 1; }
      mkdir -p "$DEST"; rm -rf "$d"; cp -r skill-recommender "$d"
      edit --arg c "node $d/recommend.js prompt" '.hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{hooks: [{type: "command", command: $c, timeout: 5}]}])'
      for ev in PostToolUse PostToolUseFailure; do
        edit --arg c "node $d/recommend.js tool" --arg ev "$ev" '.hooks[$ev] = ((.hooks[$ev] // []) + [{matcher: "*", hooks: [{type: "command", command: $c, timeout: 5}]}])'
      done
      [ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skill-index.json" ] || "$HOME/.local/bin/skill-route-sync" --quiet >/dev/null 2>&1 || true
      echo "installed skill-recommender -> $d (restart Claude Code; stats: node $d/recommend.js stats)"
    fi;;
  hook)
    name=$2
    case $name in
      lead-guard) f=lead-no-worker-agents.sh; m=${3:-'Agent|Task'};;
      review-gate) f=review-gate.sh; m=${3:-Bash};;
      mail-no-links) f=mail-no-links.sh; m=$3
        [ -n "$un" ] || [ -n "$m" ] || { echo "mail-no-links needs your mail tool names as the matcher, e.g. 'mcp__mail__send_message|mcp__mail__create_draft'"; exit 2; };;
      *) sed -n 2,6p "$0"; exit 2;;
    esac
    c="$HOME/.config/pierce-skill-kit/hooks/$f"
    edit --arg c "$c" '.hooks.PreToolUse = ((.hooks.PreToolUse // []) | map(.hooks |= map(select(.command != $c))) | map(select((.hooks | length) > 0)))'
    if [ -n "$un" ]; then echo "removed hook $name"; else
      mkdir -p "$(dirname "$c")"; cp "$KIT/hooks/$f" "$c"; chmod +x "$c"
      edit --arg c "$c" --arg m "$m" '.hooks.PreToolUse += [{matcher: $m, hooks: [{type: "command", command: $c}]}]'
      echo "installed hook $name on '$m'"
    fi;;
  *) sed -n 2,6p "$0"; exit 2;;
esac
