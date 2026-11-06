#!/bin/sh
# Route mod (claude-pick + router install), no network, no logins, no container needed:
#   sh tests/route-test.sh
# Fake accounts in a temp HOME, a stub claude that prints its config folder, usage saved by the real status line.
set -e
KIT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home XDG_CACHE_HOME=$T/home/.cache LK_CONFIG=$T/none PATH=$T/home/.local/bin:$PATH
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME/.claude" "$HOME/.local/bin" "$T/bin"
printf '#!/bin/sh\necho "CFG=${CLAUDE_CONFIG_DIR:-unset} ARGS=$*"\n' > "$T/bin/fakeclaude"; chmod +x "$T/bin/fakeclaude"
export CLAUDE_BIN=$T/bin/fakeclaude
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok: $*"; }
no() { fail=$((fail + 1)); echo "FAIL: $*"; }
check() { msg=$1; shift; if "$@"; then ok "$msg"; else no "$msg"; fi; }
ln -s "$KIT/bin/claude-acct" "$HOME/.local/bin/claude-acct"; ln -s "$KIT/bin/lk-config" "$HOME/.local/bin/lk-config"

sh "$KIT/mods/route/install.sh" >/dev/null 2>&1
check "install links claude-pick" [ -x "$HOME/.local/bin/claude-pick" ]
check "install leaves the skill router to the main installer" [ ! -e "$HOME/.claude/skill-router.md" ]

# no numbers at all yet: say so, mark no winner, auto takes the first account and says why
mkdir -p "$HOME/.claude-work"; : > "$HOME/.claude-work/.claude.json"
printf '\n' | claude-pick > "$T/menu0" 2>&1 || true
check "no data: menu says how to get numbers" grep -q 'No usage numbers yet: install the usage status line (sh mods/usage/install.sh)' "$T/menu0"
check "no data: no account marked as most room" sh -c "! grep -q 'most room' '$T/menu0'"
check "no data: auto starts the first account (main)" [ "$(claude-pick auto 2>/dev/null)" = "CFG=unset ARGS=" ]
check "no data: auto says why" sh -c "claude-pick auto 2>&1 >/dev/null | grep -q 'No usage numbers yet.*first account'"

# accounts: folders with a login (.credentials.json or .claude.json) or made by claude-acct add; never tool state
mkdir -p "$HOME/.claude-alpha" "$HOME/.claude-fresh" "$HOME/.claude-flow" "$HOME/.claude-mem"
echo '{}' > "$HOME/.claude-alpha/.credentials.json"; : > "$HOME/.claude-fresh/.kit-account"; echo '{}' > "$HOME/.claude-flow/state.json"
check "claude-acct names skips ~/.claude-flow and other non-account folders" \
  [ "$(claude-acct names | tr '\n' ' ')" = "main alpha fresh work " ]
# usage written by the real status line, one draw per account (rate_limits as Claude Code passes them)
SL=$KIT/mods/statusline/statusline.sh; future=$(( $(date +%s) + 86400 )); past=$(( $(date +%s) - 60 ))
draw() { printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus"},"rate_limits":%s}' "$T" "$2" |
  if [ "$1" = main ]; then sh "$SL"; else CLAUDE_CONFIG_DIR=$HOME/.claude-$1 sh "$SL"; fi >/dev/null 2>&1; }
draw main  "{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":70,\"resets_at\":$future}}"
draw work  "{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}"
draw alpha "{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}"
check "status line saved per-account usage" [ -s "$XDG_CACHE_HOME/pierce-skill-kit/usage-alpha.json" ]

order=$(claude-pick order | tr '\n' ' ')
check "order: alpha (20/10), work (20/40), main (70), fresh (no data) last" \
  [ "$order" = "$HOME/.claude-alpha $HOME/.claude-work $HOME/.claude $HOME/.claude-fresh " ]
check "auto starts the account with the most room and passes args" \
  [ "$(claude-pick auto -p hi 2>/dev/null)" = "CFG=$HOME/.claude-alpha ARGS=-p hi" ]
check "menu: Enter = most room" [ "$(printf '\n' | claude-pick 2>/dev/null | grep -o 'CFG=[^ ]*')" = "CFG=$HOME/.claude-alpha" ]
check "menu: 3 = third in the list (main)" [ "$(printf '3\n' | claude-pick 2>/dev/null | grep -o 'CFG=[^ ]*')" = "CFG=unset" ]
printf '\n' | claude-pick > "$T/menu" 2>&1 || true
check "menu shows week + 5h + age and marks the most room" grep -qE '1\) alpha +week 20% +5h 10% +\(just now\) +<- most room' "$T/menu"
check "menu never lists ~/.claude-flow" sh -c "! grep -qE 'flow|mem' '$T/menu' && ! claude-pick order | grep -q flow"
check "menu has data: no 'no usage numbers' line" sh -c "! grep -q 'No usage numbers' '$T/menu'"
check "menu shows ? for an account with no data" grep -qE 'fresh +week \? +5h \? *$' "$T/menu"
check "menu temp file comes from mktemp, not a fixed /tmp name" sh -c "grep -q mktemp '$KIT/mods/route/claude-pick' && ! grep -q 'claude-pick\.\\\$\\\$' '$KIT/mods/route/claude-pick'"
# bad menu input: a plain "pick 1-N", exit 2, nothing started, never a sed error and never run as a command
cd "$T"; for k in 0 9 abc '-1' '1p;e touch pwned' '99999999999999999999'; do
  rc=0; printf '%s\n' "$k" | claude-pick > "$T/bad" 2>&1 || rc=$?
  check "menu refuses '$k' with 'pick 1-4' (exit 2, starts nothing)" \
    sh -c "[ $rc = 2 ] && grep -q 'pick 1-4\$' '$T/bad' && ! grep -qiE 'CFG=|sed|invalid|illegal|expected' '$T/bad'"
done; check "menu input never runs as a command" [ ! -e "$T/pwned" ]; cd - >/dev/null
rc=0; claude-pick --version > "$T/ver" 2>&1 || rc=$?
check "an unknown option shows usage (exit 2), not an account named --version" sh -c "[ $rc = 2 ] && grep -q 'claude-pick auto' '$T/ver' && ! grep -q CFG= '$T/ver'"
check "<name> runs that account" [ "$(claude-pick work 2>/dev/null)" = "CFG=$HOME/.claude-work ARGS=" ]
rc=0; claude-pick nope >/dev/null 2>&1 || rc=$?; check "unknown account refused (exit 1)" [ "$rc" = 1 ]

# a window that already reset counts as 0%: main's weekly reset -> main is now least used
draw main "{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":90,\"resets_at\":$past}}"
check "reset window counts as 0%" [ "$(claude-pick order | head -1)" = "$HOME/.claude" ]
echo 'not json' > "$XDG_CACHE_HOME/pierce-skill-kit/usage-work.json"
check "broken usage file = no data, not a crash" [ "$(claude-pick order | tail -1)" = "$HOME/.claude-work" ]
claude-acct list > "$T/acl" 2>&1; printf '\n' | claude-pick > "$T/pk" 2>&1 || true
check "list: damaged usage file shows 'no numbers', no jq error" sh -c "grep -qE '^  work +no numbers \\(unreadable usage file\\)\$' '$T/acl' && ! grep -qi 'jq\\|parse' '$T/acl'"
check "claude-pick: damaged usage file shows 'no numbers', no jq error, carries on" sh -c "grep -q '     no numbers (unreadable usage file)' '$T/pk' && ! grep -qi 'jq\\|parse' '$T/pk'"

# a full account (>= 95% of its 5-hour or weekly window, not yet reset) is never picked and says why
in2h=$(( $(date +%s) + 7260 )); in1h=$(( $(date +%s) + 3660 )); in1d=$(( $(date +%s) + 90060 ))
draw alpha "{\"five_hour\":{\"used_percentage\":100,\"resets_at\":$in2h},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}"
draw work  "{\"five_hour\":{\"used_percentage\":0,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":22,\"resets_at\":$future}}"
draw main  "{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":60,\"resets_at\":$future}}"
check "auto skips an account at 100% of its 5h window (lower weekly % or not)" \
  [ "$(claude-pick auto -p hi 2>/dev/null)" = "CFG=$HOME/.claude-work ARGS=-p hi" ]
check "auto says which account it skipped and when it resets" \
  sh -c "claude-pick auto 2>&1 >/dev/null | grep -qx 'claude-pick: alpha: 5h at 100%, resets in 2h, skipped'"
check "order: usable by weekly %, no-data next, full last" \
  [ "$(claude-pick order | tr '\n' ' ')" = "$HOME/.claude-work $HOME/.claude $HOME/.claude-fresh $HOME/.claude-alpha " ]
printf '\n' | claude-pick > "$T/menu2" 2>&1 || true
check "menu: Enter skips the full account" grep -q "CFG=$HOME/.claude-work" "$T/menu2"
check "menu: the full account is last and says why" sh -c "grep -A1 -E '4\) alpha +week 20% +5h 100% +\(just now\)$' '$T/menu2' | grep -qx '     full: 5h at 100%, resets in 2h'"
draw work "{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":96,\"resets_at\":$in1d}}"
check "a weekly window at 96% is full too" sh -c "claude-pick auto 2>&1 >/dev/null | grep -qx 'claude-pick: work: week at 96%, resets in 1d1h, skipped'"
draw alpha "{\"five_hour\":{\"used_percentage\":100,\"resets_at\":$past},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}"
check "a full 5h window that already reset is usable again" [ "$(claude-pick order | head -1)" = "$HOME/.claude-alpha" ]
# every account full: say which resets first, start nothing, exit 1
draw alpha "{\"five_hour\":{\"used_percentage\":97,\"resets_at\":$in1h},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}"
draw main  "{\"five_hour\":{\"used_percentage\":99,\"resets_at\":$in2h},\"seven_day\":{\"used_percentage\":60,\"resets_at\":$future}}"
draw fresh "{\"five_hour\":{\"used_percentage\":1,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":100,\"resets_at\":$in1d}}"
rc=0; claude-pick auto -p hi > "$T/all" 2>&1 || rc=$?
check "all full: auto exits 1 and starts nothing" sh -c "[ $rc = 1 ] && ! grep -q CFG= '$T/all'"
check "all full: says which resets first" grep -q 'every account is full; alpha (5h at 97%, resets in 1h) resets first. Not starting Claude.' "$T/all"
printf '\n' | claude-pick > "$T/menu3" 2>&1 || true
check "all full: the menu says so and marks no account as most room" sh -c "grep -q 'Every account is full; alpha' '$T/menu3' && ! grep -q 'most room' '$T/menu3'"

# macOS: BSD stat/date (no stat -c, no date -r <file>) still give ages and ranks
mkdir -p "$T/bsd"; RS=$(command -v stat); RD=$(command -v date)
# shellcheck disable=SC2016  # the stubs' $1 / $@ are meant for the stub, not this shell
{
printf '#!/bin/sh\n[ "$1" = -c ] && { echo "stat: illegal option -- c" >&2; exit 1; }\n[ "$1" = -f ] && [ "$2" = %%m ] && exec %s -c %%Y "$3"\nexit 1\n' "$RS" > "$T/bsd/stat"
printf '#!/bin/sh\n[ "$1" = -r ] && { echo "date: illegal time format" >&2; exit 1; }\nexec %s "$@"\n' "$RD" > "$T/bsd/date"
}
chmod +x "$T/bsd/stat" "$T/bsd/date"
check "BSD stat/date: ranks the same" [ "$(PATH=$T/bsd:$PATH claude-pick order | head -1)" = "$(claude-pick order | head -1)" ]
check "BSD stat/date: menu shows each number's age" sh -c "printf '\n' | PATH='$T/bsd':\"\$PATH\" claude-pick 2>&1 | grep -qE '1\) alpha .*\(just now\)'"
check "BSD stat/date: claude-acct list shows ages" sh -c "PATH='$T/bsd':\"\$PATH\" claude-acct list | grep -qE 'alpha +5h 97% · week 20% \(just now\)'"

# claude-acct with no arguments is the same picker when claude-pick is installed
check "claude-acct menu = claude-pick menu when the route mod is installed" sh -c "printf '\n' | claude-acct 2>&1 | grep -q 'Every account is full'"

# list: plain text, one line per account, no menu prompt, most room marked
draw alpha "{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}"
draw main  "{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":60,\"resets_at\":$future}}"
draw work  "{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":30,\"resets_at\":$future}}"
draw fresh "{\"five_hour\":{\"used_percentage\":1,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":50,\"resets_at\":$future}}"
claude-pick list > "$T/list" 2>&1 < /dev/null
check "list: one line per account, week + 5h + age, most room marked, no prompt" sh -c "[ \$(wc -l < '$T/list') = 4 ] && grep -qE '^  alpha +week 20% +5h 10% +\(just now\) +<- most room\$' '$T/list' && ! grep -q 'Account number' '$T/list'"
# stale numbers (older than 24h) rank after fresh ones and auto says how old they are
touch -d '3 days ago' "$XDG_CACHE_HOME/pierce-skill-kit/usage-alpha.json"
check "stale: alpha (20%, 3d old) ranks after fresh work (30%)" [ "$(claude-pick order | head -1)" = "$HOME/.claude-work" ]
check "stale: list shows its age and no most-room mark on it" sh -c "claude-pick list | grep -E 'alpha .*\(3d ago\)\$' | grep -vq 'most room'"
touch -d '3 days ago' "$XDG_CACHE_HOME/pierce-skill-kit/usage-fresh.json" "$XDG_CACHE_HOME/pierce-skill-kit/usage-work.json" "$XDG_CACHE_HOME/pierce-skill-kit/usage-main.json"
check "all stale: auto still starts one and says (numbers 3d old)" sh -c "claude-pick auto 2>&1 | grep -q 'claude-pick: .*(numbers 3d old)' && ! claude-pick auto 2>&1 | grep -q 'most room'"
draw alpha "{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}"
check "fresh numbers again: auto says most room" sh -c "claude-pick auto 2>&1 | grep -qx 'claude-pick: alpha (most room)' || claude-pick auto 2>&1 | grep -q 'CFG=.*alpha'"

# an account folder with a space is ONE account: no ghost rows, no link errors, quoted everywhere
mkdir -p "$HOME/.claude-my acct"; : > "$HOME/.claude-my acct/.kit-account"
draw "my acct" "{\"five_hour\":{\"used_percentage\":1,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":2,\"resets_at\":$future}}"
check "space: claude-acct names lists 'my acct' once" [ "$(claude-acct names | grep -c 'my')" = 1 ] 
claude-acct run "my acct" > "$T/sp" 2>&1 || true
check "space: run starts it with its folder and no ln errors" sh -c "grep -q 'CFG=$HOME/.claude-my acct' '$T/sp' && ! grep -qi 'ln:\|failed' '$T/sp'"
check "space: list shows one 'my acct' row, no 'acct' ghost" sh -c "claude-pick list | grep -c 'my acct' | grep -qx 1 && ! claude-pick list | grep -qE '^  (my|acct) +week'"
check "space: auto picks it (most room) with the right folder" [ "$(claude-pick auto 2>/dev/null)" = "CFG=$HOME/.claude-my acct ARGS=" ]
check "space: order prints its folder on one line" sh -c "claude-pick order | grep -cx '$HOME/.claude-my acct' | grep -qx 1"
check "space: menu 1 = it" [ "$(printf '1\n' | claude-pick 2>/dev/null | grep -o 'CFG=.*ARGS')" = "CFG=$HOME/.claude-my acct ARGS" ]
check "space: claude-acct menu lists it once" sh -c "printf '\n' | CLAUDE_BIN=true PATH='$T/nopick':\$PATH claude-acct 2>&1 | grep -c 'my acct' | grep -qx 1" 

# the status line for a config folder not named ~/.claude-*: its bars show, usage saved under its folder name
mkdir -p "$T/opt/x/claude"
out=$(printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":%s}}}' "$T" "$future" | CLAUDE_CONFIG_DIR=$T/opt/x/claude sh "$SL" 2>&1)
check "other folder: no error, usage saved as usage-claude.json" sh -c "[ -s '$XDG_CACHE_HOME/pierce-skill-kit/usage-claude.json' ] && ! printf '%s' '$out' | grep -qi 'cannot\|nonexistent'"
check "other folder: its 5h bar is drawn" sh -c "printf '%s' '$out' | grep -q '5h .*5%'"
rm -f "$XDG_CACHE_HOME/pierce-skill-kit/usage-claude.json"

# safety: nothing in the route mod reads logins or calls a usage API, and nothing retries on another account
hits=$(grep -rniE 'credentials|accessToken|oauth|api\.anthropic|/api/|curl |fetch\(|failover' \
  "$KIT/mods/route" "$KIT/skills/claude-accounts" || true)
check "no login/token reads, no usage API, no failover in mods/route or the claude-accounts skill" [ -z "$hits" ]
[ -z "$hits" ] || echo "$hits"

sh "$KIT/mods/route/install.sh" --uninstall >/dev/null
check "uninstall removes claude-pick" [ ! -e "$HOME/.local/bin/claude-pick" ]
# claude-acct's own menu (no route mod): Enter = main, bad input gets a plain "pick 1-N"
check "claude-acct menu: Enter = main" [ "$(printf '\n' | claude-acct 2>/dev/null | grep -o 'CFG=[^ ]*')" = "CFG=unset" ]
check "claude-acct menu: 2 = second account" [ "$(printf '2\n' | claude-acct 2>/dev/null | grep -o 'CFG=[^ ]*')" = "CFG=$HOME/.claude-alpha" ]
cd "$T"; for k in 0 9 abc '1p;e touch pwned2' '99999999999999999999'; do
  rc=0; printf '%s\n' "$k" | claude-acct > "$T/bad" 2>&1 || rc=$?
  check "claude-acct menu refuses '$k' with 'pick 1-5'" sh -c "[ $rc = 2 ] && grep -q 'pick 1-5\$' '$T/bad' && ! grep -qiE 'CFG=|sed|invalid|illegal|expected' '$T/bad'"
done; check "claude-acct menu input never runs as a command" [ ! -e "$T/pwned2" ]; cd - >/dev/null
echo "route-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
