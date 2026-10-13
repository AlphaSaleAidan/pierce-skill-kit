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
grep -qiE 'failover|least.used' "$(command -v claude-acct)" && fail "no failover/least-used logic in the public tool"
echo "ALL ACCOUNTS TESTS PASSED"
