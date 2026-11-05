#!/bin/sh
# Usage mod: the status line's bars / ∞ mark / budgets / busy line from fixed JSON, and mods/usage/install.sh in a
# temp HOME (no network, no docker):
#   sh tests/usage-test.sh
set -e
command -v jq >/dev/null || { echo "needs jq"; exit 1; }
KIT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home PATH=$T/bin:$PATH; unset CLAUDE_CONFIG_DIR XDG_CACHE_HOME LK_CONFIG CLAUDE_USAGE_BUDGETS
mkdir -p "$HOME" "$T/bin"
fail() { echo "FAIL: $*"; exit 1; }
# --- install: status line + busy-line helper, nothing else
sh "$KIT/mods/usage/install.sh" >/dev/null
S=$HOME/.claude/settings.json; SL=$HOME/.config/pierce-skill-kit/mods/statusline/statusline.sh
jq -e '.statusLine.command | endswith("statusline/statusline.sh")' "$S" >/dev/null || fail "statusline not set"
[ -f "${SL%/*}/health.sh" ] || fail "health.sh missing"
echo "ok: install sets the status line and the busy-line helper"
# the safe version: no login tokens, no private usage API, anywhere in the usage mod or the status line
! grep -rniE 'credentials|accesstoken|oauth|api\.anthropic|failover' "$KIT/mods/usage" "$KIT/mods/statusline" || fail "usage mod reads tokens or a private API"
echo "ok: no token reading, no private usage API"

# --- status line
now=$(date +%s); cache=$HOME/.cache/pierce-skill-kit
draw() { rm -rf "$HOME/.cache/statusline"; printf '%s' "$1" | sh "$SL" | sed 's/\x1b\[[0-9;]*m//g'; }
j() { echo "{\"workspace\":{\"current_dir\":\"$T\"},\"model\":{\"display_name\":\"Opus\"},\"rate_limits\":$1}"; }
out=$(draw "$(j "{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 7200 + 60))},\"seven_day\":{\"used_percentage\":91,\"resets_at\":$((now + 90000 + 60))}}")")
echo "$out" | grep -q "5h ▰▰▱▱▱ 40% ↻2h   week ▰▰▰▰▰ 91% ↻1d1h" || { echo "$out"; fail "single-account bars"; }
echo "$out" | grep -q "▶" && fail "single account should not be tagged"
echo "ok: one account: 5h + weekly bars with reset times"
echo "{\"seven_day\":{\"used_percentage\":10,\"resets_at\":$((now + 3600))}}" > "$cache/usage-work.json"
echo "{\"five_hour\":{\"used_percentage\":99,\"resets_at\":$((now - 60))},\"seven_day\":{\"used_percentage\":50}}" > "$cache/usage-spare.json"
out=$(draw "$(j "{\"five_hour\":{\"used_percentage\":40},\"seven_day\":{\"used_percentage\":91}}")")
echo "$out" | grep -q "▶ main  5h ▰▰▱▱▱ 40%" || { echo "$out"; fail "current account line"; }
echo "$out" | grep -q "  work  5h ∞   week ▰▱▱▱▱ 10%" || { echo "$out"; fail "infinity mark (no 5h window)"; }
echo "$out" | grep -q "  spare  5h ▱▱▱▱▱ 0%" || { echo "$out"; fail "a window past its reset should read 0%"; }
echo "LK_USAGE_NO_5H=\"main\"" > "$HOME/.config/pierce-skill-kit/config"
draw "$(j '{"five_hour":{"used_percentage":40},"seven_day":{"used_percentage":91}}')" | grep -q "▶ main  5h ∞" || fail "LK_USAGE_NO_5H"
echo "ok: several accounts: one line each, ▶ on this one, ∞ for no 5-hour limit, reset windows read 0%"
echo '{"site":{"name":"site","limit_pct":20,"baseline_pct":80,"carried":0},"docs":{"name":"docs","limit_pct":5,"baseline_pct":85,"carried":0}}' > "$HOME/.claude/usage-budgets.json"
draw "$(j '{"seven_day":{"used_percentage":91}}')" | grep -q "budget site 11/20% · docs 6/5%" || fail "budgets line"
echo "ok: claude-usage budgets show used/limit"
printf '#!/bin/sh\necho "warn CPU load 150%%"\n' > "${SL%/*}/health.sh"
draw "$(j '{}')" | grep -q "⚠ server busy CPU load 150%" || fail "busy line"
printf '#!/bin/sh\necho ok\n' > "${SL%/*}/health.sh"
draw "$(j '{}')" | grep -q "server busy" && fail "busy line when ok"
echo "ok: server-busy line shows only when the health check warns"

# --- uninstall
sh "$KIT/mods/usage/install.sh" --uninstall >/dev/null
jq -e '.statusLine == null' "$S" >/dev/null || fail "uninstall"
echo "ok: uninstall removes the status line"
echo "ALL USAGE TESTS PASSED"
