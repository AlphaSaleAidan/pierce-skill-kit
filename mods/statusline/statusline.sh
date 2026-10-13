#!/bin/sh
# Statusline: folder + git branch/dirty count + model + Claude config in use, then 5-hour + weekly plan usage
# (from Claude Code's own rate_limits input), hub counts (projects-hub mod)
# and a server-overload warning (agent-board's health check). Cached 30 s per folder+model so many tabs stay cheap.
# Settings: "statusLine": { "type": "command", "command": "sh <this file>" }   Needs: jq. Optional: STATUSLINE_EXTRA
# (a command whose output is appended to line 1, fed the same JSON on stdin).
here=$(cd "$(dirname "$0")" && pwd)
in=$(cat)
dir=$(printf '%s' "$in" | jq -r '.workspace.current_dir // empty'); dir=${dir:-$PWD}
model=$(printf '%s' "$in" | jq -r '.model.display_name // empty')
cache=${XDG_CACHE_HOME:-$HOME/.cache}/statusline; mkdir -p "$cache"
# Save this account's latest plan usage for `claude-acct list` (main = ~/.claude, else the .claude-<name> folder).
acct_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}; acct_dir=${acct_dir%/}; acct=${acct_dir##*/.claude-}; [ "$acct_dir" = "$HOME/.claude" ] && acct=main
rl=$(printf '%s' "$in" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$rl" ] && [ "$rl" != "{}" ]; then u=${XDG_CACHE_HOME:-$HOME/.cache}/pierce-skill-kit; mkdir -p "$u"; printf '%s' "$rl" > "$u/usage-$acct.json"; fi
ck=$cache/$(printf '%s|%s|%s' "$dir" "$model" "${CLAUDE_CONFIG_DIR:-default}" | cksum | cut -d' ' -f1)
if [ -f "$ck" ] && [ $(( $(date +%s) - $(stat -c %Y "$ck") )) -lt 30 ]; then cat "$ck"; exit 0; fi
exec 3>&1 1>"$ck.$$"
br=$(git -C "$dir" branch --show-current 2>/dev/null)
dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l)
line1="\033[1;34m${dir##*/}\033[0m"
[ -n "$br" ] && line1="$line1 \033[2m⏇\033[0m $br" && [ "$dirty" -gt 0 ] && line1="$line1 \033[33m~$dirty\033[0m"
cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}; cfg=${cfg%/}
line1="$line1  \033[2m│\033[0m  \033[35m$model\033[0m  \033[2m│\033[0m  \033[36m${cfg##*/}\033[0m"
extra=''; [ -n "$STATUSLINE_EXTRA" ] && extra=$(printf '%s' "$in" | sh -c "$STATUSLINE_EXTRA" 2>/dev/null)
printf '%b   %s' "$line1" "$extra"
# Plan usage: the 5-hour and weekly windows Claude Code itself passes in (rate_limits; appears after the first reply).
usage=$(printf '%s' "$in" | jq -r --argjson now "$(date +%s)" '
  def bar(p): ([5, ((p // 0) / 20 | round)] | min) as $n | ("▰" * $n) + ("▱" * (5 - $n));
  def col(p): if p >= 85 then "\u001b[31m" elif p >= 60 then "\u001b[33m" else "\u001b[32m" end;
  def left(r): (try (if (r|type) == "number" then r else (r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) end) catch null) as $t
    | if $t == null then "" else ([0, ($t - $now) / 60 | floor] | max) as $m
      | if $m >= 1440 then "\($m / 1440 | floor)d\($m % 1440 / 60 | floor)h" elif $m >= 60 then "\($m / 60 | floor)h" else "\($m)m" end end;
  def win(lbl; w): if w == null or w.used_percentage == null then empty else
    "\(lbl) \(col(w.used_percentage))\(bar(w.used_percentage)) \(w.used_percentage | round)%\u001b[0m \u001b[2m↻\(left(w.resets_at))\u001b[0m" end;
  [win("5h"; .rate_limits.five_hour), win("week"; .rate_limits.seven_day)] | join("   ")' 2>/dev/null)
[ -n "$usage" ] && printf '\n%s' "$usage"
# Hub counts, if the projects-hub mod is installed next to this one; refreshed in the background every 5 min.
hub=${HUB_CACHE:-$HOME/.cache/projects-hub.json}; gather=$here/../projects-hub/bin/gather.py
if [ -f "$gather" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$hub" 2>/dev/null || echo 0) ))
  [ "$age" -gt 300 ] && setsid nohup python3 "$gather" >/dev/null 2>&1 < /dev/null &
  [ -s "$hub" ] && printf '\n%s' "$(jq -r '"\([.sessions[]|select(.live)]|length) open sessions · \(.prs|length) PRs · \(.projects|length) active · \(.services|length) ports"' "$hub")"
fi
health=$here/../agent-board/bin/health.sh
h=$( [ -f "$health" ] && sh "$health" 2>/dev/null )
case "$h" in
  crit*) printf '\n\033[1;41;97m SERVER OVERLOADED \033[0m \033[31m%s\033[0m' "${h#crit }";;
  warn*) printf '\n\033[1;33m⚠ server busy\033[0m \033[33m%s\033[0m' "${h#warn }";;
esac
exec 1>&3; mv "$ck.$$" "$ck"; cat "$ck"
exit 0
