#!/bin/sh
# Statusline: folder + git branch/dirty count + model + Claude config in use, then 5-hour + weekly plan usage per
# account (from Claude Code's own rate_limits input; ∞ = no 5-hour limit, dimmed when over 6h old), claude-usage MCP budgets, hub counts (projects-hub mod)
# and a server-overload warning (agent-board's health check). Cached 30 s per folder+model so many tabs stay cheap.
# Settings: "statusLine": { "type": "command", "command": "sh <this file>" }   Needs: jq. Optional: STATUSLINE_EXTRA
# (a command whose output is appended to line 1, fed the same JSON on stdin).
here=$(cd "$(dirname "$0")" && pwd)
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }   # GNU, then BSD/macOS
in=$(cat)
dir=$(printf '%s' "$in" | jq -r '.workspace.current_dir // empty'); dir=${dir:-$PWD}
model=$(printf '%s' "$in" | jq -r '.model.display_name // empty')
cache=${XDG_CACHE_HOME:-$HOME/.cache}/statusline; mkdir -p "$cache"
# Save this account's latest plan usage for `claude-acct list` (main = ~/.claude, else the .claude-<name> folder).
acct_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}; acct_dir=${acct_dir%/}; acct=${acct_dir##*/.claude-}; [ "$acct_dir" = "$HOME/.claude" ] && acct=main
rl=$(printf '%s' "$in" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$rl" ] && [ "$rl" != "{}" ]; then u=${XDG_CACHE_HOME:-$HOME/.cache}/pierce-skill-kit; mkdir -p "$u"; printf '%s' "$rl" > "$u/usage-$acct.json"; fi
ck=$cache/$(printf '%s|%s|%s' "$dir" "$model" "${CLAUDE_CONFIG_DIR:-default}" | cksum | cut -d' ' -f1)
if [ -f "$ck" ] && [ $(( $(date +%s) - $(mtime "$ck") )) -lt 30 ]; then cat "$ck"; exit 0; fi
exec 3>&1 1>"$ck.$$"
br=$(git -C "$dir" branch --show-current 2>/dev/null)
dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l)
line1="\033[1;34m${dir##*/}\033[0m"
[ -n "$br" ] && line1="$line1 \033[2m⏇\033[0m $br" && [ "$dirty" -gt 0 ] && line1="$line1 \033[33m~$dirty\033[0m"
cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}; cfg=${cfg%/}
line1="$line1  \033[2m│\033[0m  \033[35m$model\033[0m  \033[2m│\033[0m  \033[36m${cfg##*/}\033[0m"
extra=''; [ -n "$STATUSLINE_EXTRA" ] && extra=$(printf '%s' "$in" | sh -c "$STATUSLINE_EXTRA" 2>/dev/null)
printf '%b   %s' "$line1" "$extra"
# Plan usage, one line per account: the 5-hour and weekly windows Claude Code passes in (rate_limits, saved above
# per account each time a tab draws). Several accounts: ▶ marks this one. ∞ = no 5-hour limit, only for accounts
# listed in LK_USAGE_NO_5H; a missing 5-hour window otherwise shows "5h –". Numbers saved over 6h ago are dimmed
# and marked "(old: 7h ago)". The kit config is read as text (one sed), never run as shell.
no5h=${LK_USAGE_NO_5H-$(sed -n 's/^[[:space:]]*\(export[[:space:]]*\)\{0,1\}LK_USAGE_NO_5H=//p' "${LK_CONFIG:-$HOME/.config/pierce-skill-kit/config}" 2>/dev/null | tail -1 | tr -d "\"'")}
usage=$(for f in "${XDG_CACHE_HOME:-$HOME/.cache}"/pierce-skill-kit/usage-*.json; do
    [ -s "$f" ] && jq -c --arg f "${f##*/}" --argjson m "$(mtime "$f")" '{n: ($f | sub("^usage-"; "") | sub("\\.json$"; "")), m: $m, r: .}' "$f" 2>/dev/null
  done | jq -rn --argjson now "$(date +%s)" --arg cur "$acct" --arg no5h " $no5h " '
  def bar(p): ([5, ((p // 0) / 20 | round)] | min) as $n | ("▰" * $n) + ("▱" * (5 - $n));
  def col(p; old): if old then "\u001b[2m" elif p >= 85 then "\u001b[31m" elif p >= 60 then "\u001b[33m" else "\u001b[32m" end;
  def ts(r): try (if (r|type) == "number" then r else (r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) end) catch null;
  def dur(s): ([0, s / 60 | floor] | max) as $m
      | if $m >= 1440 then "\($m / 1440 | floor)d\($m % 1440 / 60 | floor)h" elif $m >= 60 then "\($m / 60 | floor)h" else "\($m)m" end;
  def left(r): ts(r) as $t | if $t == null then "" else dur($t - $now) end;
  def win(lbl; w; old): if w == null or w.used_percentage == null then empty else
    (if (ts(w.resets_at) // $now + 1) < $now then 0 else w.used_percentage end) as $p   # window already reset: 0%
    | "\(lbl) \(col($p; old))\(bar($p)) \($p | round)%\u001b[0m \u001b[2m↻\(left(w.resets_at))\u001b[0m" end;
  [inputs | .n as $n | (($now - .m) > 21600) as $old
    | .w = [if ($no5h | contains(" \($n) ")) then "5h \(if $old then "\u001b[2m" else "\u001b[1;32m" end)∞\u001b[0m"
            elif .r.five_hour == null and .r.seven_day != null then "5h \u001b[2m–\u001b[0m"
            else win("5h"; .r.five_hour; $old) end, win("week"; .r.seven_day; $old)] | select(.w | length > 0)
    | .w += (if $old then ["\u001b[2m(old: \(($now - .m) / 3600 | floor | if . >= 24 then "\(. / 24 | floor)d" else "\(.)h" end) ago)\u001b[0m"] else [] end)] as $a
  | $a[] | (if ($a | length) > 1 then (if .n == $cur then "\u001b[1;36m▶ \(.n)\u001b[0m  " else "  \(.n)  " end) else "" end) + (.w | join("   "))
  ')
[ -n "$usage" ] && printf '\n%s' "$usage"
# Per-project budgets from the claude-usage MCP (budget_start), measured against this account's weekly % now.
# shortcut: ignores a weekly reset since the MCP last checked (the MCP banks it on its next budget_check).
bf=${CLAUDE_USAGE_BUDGETS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-budgets.json}
wk=$(printf '%s' "$in" | jq '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
[ -s "$bf" ] && [ -n "$wk" ] && b=$(jq -r --argjson wk "$wk" '[.[] | ((.carried // 0) + $wk - (.baseline_pct // 0) | . * 10 | round / 10) as $u
  | "\(if $u >= .limit_pct then "\u001b[31m" else "" end)\(.name) \($u)/\(.limit_pct)%\u001b[0m"] | select(length > 0) | "budget " + join(" · ")' "$bf" 2>/dev/null) \
  && [ -n "$b" ] && printf '\n%s' "$b"
# Hub counts, if the projects-hub mod is installed next to this one; refreshed in the background every 5 min.
hub=${HUB_CACHE:-$HOME/.cache/projects-hub.json}; gather=$here/../projects-hub/bin/gather.py
if [ -f "$gather" ]; then
  age=$(( $(date +%s) - $(mtime "$hub") ))
  [ "$age" -gt 300 ] && setsid nohup python3 "$gather" >/dev/null 2>&1 < /dev/null &
  [ -s "$hub" ] && printf '\n%s' "$(jq -r '"\([.sessions[]|select(.live)]|length) open sessions · \(.prs|length) PRs · \(.projects|length) active · \(.services|length) ports"' "$hub")"
fi
health=$here/../agent-board/bin/health.sh; [ -f "$health" ] || health=$here/health.sh   # usage mod copies one here
h=$( [ -f "$health" ] && sh "$health" 2>/dev/null )
case "$h" in
  crit*) printf '\n\033[1;41;97m SERVER OVERLOADED \033[0m \033[31m%s\033[0m' "${h#crit }";;
  warn*) printf '\n\033[1;33m⚠ server busy\033[0m \033[33m%s\033[0m' "${h#warn }";;
esac
exec 1>&3; mv "$ck.$$" "$ck"; cat "$ck"
exit 0
