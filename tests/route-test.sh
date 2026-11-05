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
check "install copies the router template" grep -q 'Skill router' "$HOME/.claude/skill-router.md"
echo '# mine' > "$HOME/.claude/skill-router.md"; sh "$KIT/mods/route/install.sh" >/dev/null 2>&1
check "re-install keeps your router" grep -q '^# mine' "$HOME/.claude/skill-router.md"

# no numbers at all yet: say so, mark no winner, auto takes the first account and says why
mkdir -p "$HOME/.claude-work"; : > "$HOME/.claude-work/.claude.json"
printf '\n' | claude-pick > "$T/menu0" 2>&1 || true
check "no data: menu says how to get numbers" grep -q 'No usage numbers yet: install the usage status line (sh mods/usage/install.sh)' "$T/menu0"
check "no data: no account marked least used" sh -c "! grep -q 'least used' '$T/menu0'"
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
check "auto starts the least-used account and passes args" \
  [ "$(claude-pick auto -p hi 2>/dev/null)" = "CFG=$HOME/.claude-alpha ARGS=-p hi" ]
check "menu: Enter = least used" [ "$(printf '\n' | claude-pick 2>/dev/null | grep -o 'CFG=[^ ]*')" = "CFG=$HOME/.claude-alpha" ]
check "menu: 3 = third least used (main)" [ "$(printf '3\n' | claude-pick 2>/dev/null | grep -o 'CFG=[^ ]*')" = "CFG=unset" ]
printf '\n' | claude-pick > "$T/menu" 2>&1 || true
check "menu shows week + 5h + age and marks the least used" grep -qE '1\) alpha +week 20% +5h 10% +\(just now\) +<- least used' "$T/menu"
check "menu never lists ~/.claude-flow" sh -c "! grep -qE 'flow|mem' '$T/menu' && ! claude-pick order | grep -q flow"
check "menu has data: no 'no usage numbers' line" sh -c "! grep -q 'No usage numbers' '$T/menu'"
check "menu shows ? for an account with no data" grep -qE 'fresh +week \? +5h \? *$' "$T/menu"
check "menu temp file comes from mktemp, not a fixed /tmp name" sh -c "grep -q mktemp '$KIT/mods/route/claude-pick' && ! grep -q 'claude-pick\.\\\$\\\$' '$KIT/mods/route/claude-pick'"
rc=0; printf 'w x\n' | claude-pick >/dev/null 2>&1 || true; check "menu ignores non-numbers (no sed tricks)" [ ! -e x ]
rc=0; printf '9\n' | claude-pick > "$T/bad" 2>&1 || rc=$?
check "menu refuses a bad number (exit 2, starts nothing)" sh -c "[ $rc = 2 ] && ! grep -q CFG= '$T/bad'"
check "<name> runs that account" [ "$(claude-pick work 2>/dev/null)" = "CFG=$HOME/.claude-work ARGS=" ]
rc=0; claude-pick nope >/dev/null 2>&1 || rc=$?; check "unknown account refused (exit 1)" [ "$rc" = 1 ]

# a window that already reset counts as 0%: main's weekly reset -> main is now least used
draw main "{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":90,\"resets_at\":$past}}"
check "reset window counts as 0%" [ "$(claude-pick order | head -1)" = "$HOME/.claude" ]
echo 'not json' > "$XDG_CACHE_HOME/pierce-skill-kit/usage-work.json"
check "broken usage file = no data, not a crash" [ "$(claude-pick order | tail -1)" = "$HOME/.claude-work" ]

# safety: nothing in the route mod reads logins or calls a usage API, and nothing retries on another account
hits=$(grep -rniE 'credentials|accessToken|oauth|api\.anthropic|/api/|curl |fetch\(|failover' \
  "$KIT/mods/route" "$KIT/skills/claude-accounts" || true)
check "no login/token reads, no usage API, no failover in mods/route or the claude-accounts skill" [ -z "$hits" ]
[ -z "$hits" ] || echo "$hits"

sh "$KIT/mods/route/install.sh" --uninstall >/dev/null
check "uninstall removes claude-pick, keeps the router" sh -c "[ ! -e '$HOME/.local/bin/claude-pick' ] && [ -f '$HOME/.claude/skill-router.md' ]"
echo "route-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
