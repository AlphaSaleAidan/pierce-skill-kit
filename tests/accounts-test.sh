#!/bin/sh
# Two Claude accounts in a throwaway container (a stand-in prints which config dir it got):
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/accounts-test.sh
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq tmux jq procps >/dev/null
fail() { echo "FAIL: $*"; exit 1; }
printf '#!/bin/sh\necho "CFG=${CLAUDE_CONFIG_DIR:-unset}"; sleep 30\n' > /usr/local/bin/fakeclaude; chmod +x /usr/local/bin/fakeclaude
cp -r /kit /tmp/kit && cd /tmp/kit && sh install.sh --yes >/dev/null
export PATH=$HOME/.local/bin:$PATH CLAUDE_BIN=fakeclaude
echo '{"oauth":"fake"}' > ~/.claude/.credentials.json
claude-acct add work > /tmp/add.log 2>&1 & sleep 1
[ -L ~/.claude-work/skills ] && [ "$(readlink ~/.claude-work/skills)" = "$HOME/.claude/skills" ] || fail "skills not shared"
[ -L ~/.claude-work/CLAUDE.md ] || fail "CLAUDE.md not shared"
[ ! -e ~/.claude-work/.credentials.json ] || fail "login was shared (must stay private)"
grep -q "CFG=$HOME/.claude-work" /tmp/add.log || fail "add did not start Claude on the new account"
echo "ok: add shares skills/CLAUDE.md, keeps the login private, opens Claude on the new account"
[ "$(timeout 2 claude-acct run work | head -1)" = "CFG=$HOME/.claude-work" ] || fail "run work"
[ "$(CLAUDE_CONFIG_DIR=$HOME/.claude-work timeout 2 claude-acct run main | head -1)" = "CFG=unset" ] || fail "run main"
echo "ok: run picks the right config dir (main unsets CLAUDE_CONFIG_DIR)"
SL=$HOME/.config/pierce-skill-kit/mods/statusline/statusline.sh
echo '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":71}}}' | CLAUDE_CONFIG_DIR=$HOME/.claude-work sh $SL >/dev/null
claude-acct list | grep -qE 'work +5h 24% · week 71%' || { claude-acct list; fail "list usage"; }
claude-acct list | grep -qE 'main +no data yet' || fail "main should have no data yet"
echo "ok: statusline saves each account's rate_limits; list shows them"
echo "LK_CLAUDE=cat" >> ~/.config/pierce-skill-kit/config; lead -d >/dev/null; mkdir -p ~/proj; claude-tab ~/proj -n proj -a work >/dev/null; sleep 1
tmux capture-pane -p -t hub:proj | grep -q "CFG=$HOME/.claude-work" || fail "claude-tab -a"
echo "ok: claude-tab -a work opens the tab on that account"
# --- name validation: refused with exit 2, nothing created
before=$(ls -d ~/.claude-* | sort | tr '\n' ' ')
for bad in main Bad_Name UPPER -lead 'a b' ../x ''; do
  rc=0; claude-acct add "$bad" >/tmp/bad.log 2>&1 </dev/null || rc=$?
  [ "$rc" = 2 ] || fail "add '$bad' should exit 2 (got $rc)"
  grep -q usage /tmp/bad.log || fail "add '$bad' printed no usage"
done
rc=0; claude-acct add >/dev/null 2>&1 </dev/null || rc=$?; [ "$rc" = 2 ] || fail "add with no name should exit 2"
[ "$(ls -d ~/.claude-* | sort | tr '\n' ' ')" = "$before" ] || fail "a refused add created a directory"
[ ! -e ~/.claude-main ] && [ ! -e ~/.claude-Bad_Name ] || fail "refused names left directories"
echo "ok: add refuses main, Bad_Name, empty and other bad names (exit 2), creates nothing"

# --- run of an unknown account
rc=0; claude-acct run nope >/tmp/nope.log 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "run nope should exit 1 (got $rc)"
grep -q 'no account at' /tmp/nope.log && grep -q 'claude-acct add' /tmp/nope.log || fail "run nope error not clear"
grep -q CFG= /tmp/nope.log && fail "run nope started Claude"
[ ! -e ~/.claude-nope ] || fail "run nope created the account"
rc=0; claude-acct run >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "run with no name should exit 2"
echo "ok: run nope errors clearly (exit 1) and starts nothing"

# --- shared link: later files and new top-level items; private items stay private
echo hello > ~/.claude/skills/late.md
[ "$(cat ~/.claude-work/skills/late.md)" = hello ] || fail "a skill added later is not visible from the account"
echo "# late" > ~/.claude/late-note.md; mkdir -p ~/.claude/newdir
echo '{}' > ~/.claude/.claude.json; mkdir -p ~/.claude/my-cache ~/.claude/cache; echo x > ~/.claude/todo.lock
timeout 2 claude-acct run work >/dev/null 2>&1 || true
[ -L ~/.claude-work/late-note.md ] && [ -L ~/.claude-work/newdir ] || fail "new top-level items not linked on the next run"
[ "$(cat ~/.claude-work/late-note.md)" = "# late" ] || fail "linked note unreadable"
for p in .credentials.json .claude.json my-cache cache todo.lock; do
  [ ! -e ~/.claude-work/$p ] && [ ! -L ~/.claude-work/$p ] || fail "private item $p was linked"
done
echo "ok: later skills are visible, new top-level items link on the next run, private items never link"

# --- three accounts: list shows all, usage stays per account
timeout 2 claude-acct add alpha >/dev/null 2>&1 || true; timeout 2 claude-acct add beta >/dev/null 2>&1 || true
mkdir -p ~/.cache/pierce-skill-kit
echo '{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":20}}' > ~/.cache/pierce-skill-kit/usage-alpha.json
claude-acct list > /tmp/list.log
for n in main work alpha beta; do grep -qE "^ +$n " /tmp/list.log || fail "list is missing $n"; done
[ "$(wc -l < /tmp/list.log)" = 4 ] || fail "list should show exactly 4 accounts"
grep -qE 'alpha +5h 10% · week 20%' /tmp/list.log || fail "alpha usage missing"
grep -E '^ +beta ' /tmp/list.log | grep -q 'no data yet' || fail "alpha usage leaked into beta"
grep -E '^ +work ' /tmp/list.log | grep -q 'week 71%' || fail "work usage changed"
grep -E '^ +main ' /tmp/list.log | grep -q 'no data yet' || fail "usage leaked into main"
echo "ok: list shows every account; one account's usage never shows on another"

# --- the picker
claude-acct </dev/null >/tmp/pick0.log 2>&1 || true
grep -q '1) main' /tmp/pick0.log || fail "picker did not list accounts"
second=$(claude-acct list | sed -n 2p | awk '{print $1}')
[ "$(printf '2\n' | timeout 2 claude-acct 2>/dev/null | grep -o "CFG=.*")" = "CFG=$HOME/.claude-$second" ] || fail "picker 2 did not start account $second"
[ "$(printf '\n' | timeout 2 claude-acct 2>/dev/null | grep -o "CFG=.*")" = "CFG=unset" ] || fail "picker Enter did not start main"
rc=0; printf '99\n' | claude-acct >/tmp/pick99.log 2>&1 || rc=$?
[ "$rc" = 2 ] && grep -q 'no such number' /tmp/pick99.log && ! grep -q CFG= /tmp/pick99.log || fail "picker accepted a bad number"
echo "ok: piping 2 into claude-acct starts the 2nd account; Enter = main; a bad number is refused"

# --- claude-tab -a with an unknown account
wins=$(tmux list-windows -a -F '#{window_name}' | sort | tr '\n' ' ')
mkdir -p ~/proj2; rc=0; claude-tab ~/proj2 -n ghost -a nope >/tmp/tab.log 2>&1 || rc=$?; sleep 2
[ "$rc" = 1 ] && grep -q "no account 'nope'" /tmp/tab.log || fail "claude-tab -a nope should refuse before opening a window (rc=$rc)"
# claude-tab does not pre-check the account: the window opens, claude-acct refuses, and the window closes with it
tmux list-windows -a -F '#{window_name}' | grep -qx ghost && fail "claude-tab -a nope left a window open"
[ "$(tmux list-windows -a -F '#{window_name}' | sort | tr '\n' ' ')" = "$wins" ] || fail "claude-tab -a nope changed the window list"
[ ! -e ~/.claude-nope ] || fail "claude-tab -a nope created the account"
echo "ok: claude-tab -a nope starts nothing and leaves no window behind"

grep -qiE 'failover|least.used' "$(command -v claude-acct)" && fail "no failover/least-used logic in the public tool"
echo "ALL ACCOUNTS TESTS PASSED"
