#!/bin/sh
# Jake's reports (yellow copy highlight, terminals closing, lost context) as tests, on a fresh user. Run per tmux:
#   for i in ubuntu:22.04 debian:12 debian:stable-slim; do docker run --rm -v "$PWD:/kit:ro" $i sh /kit/tests/views-test.sh; done
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq tmux procps bsdutils >/dev/null 2>&1
useradd -m jake
cp -r /kit /tmp/kit && chown -R jake /tmp/kit
su jake -s /bin/sh -c '
set -e
export PATH=$HOME/.local/bin:$PATH TERM=xterm-256color
fail() { echo "FAIL ($(tmux -V)): $*"; tmux list-sessions; exit 1; }
printf "#!/bin/sh\necho \"ARGS: \$*\"; exec cat\n" > /tmp/fakeclaude; chmod +x /tmp/fakeclaude
# 1. tmux already running when the kit is installed (it never read the kit settings)
tmux new-session -d -s before
cd /tmp/kit && ./install.sh --defaults >/dev/null 2>&1
echo "LK_CLAUDE=/tmp/fakeclaude" >> ~/.config/pierce-skill-kit/config
mkdir -p ~/a ~/b ~/c
lead -d; claude-tab ~/a -n a >/dev/null; claude-tab ~/b -n b >/dev/null; claude-tab ~/c -n c >/dev/null
[ "$(tmux show -gwv mode-style)" = "bg=yellow,fg=black" ] || fail "setup: expected the old server to lack the kit settings"
view() { script -qfc "tab-view $*" /dev/null >/dev/null 2>&1 & sleep 1; tmux list-sessions -F "#S #{session_created}" | grep "^view-" | sort -k2 -n | tail -1 | cut -d" " -f1; }
alive() { tmux has-session -t "$1" 2>/dev/null; }
t1=$(view hub:Lead)
[ "$(tmux show -gv @pierce-skill-kit)" = 1 ] || fail "tab-view did not load the kit settings into the running tmux"
y=$( { tmux show -g; tmux show -gw; } | grep -- "-style" | grep -c yellow || true)
[ "$y" = 0 ] || fail "$y style options still yellow: $( { tmux show -g; tmux show -gw; } | grep -- -style | grep yellow | tr "\n" " ")"
echo "ok: an already-running tmux gets the kit settings, no yellow styles left"
# 2. terminal 1 moves to tab b; tab a closes (numbers shift); terminal 2 opens hub:2 (now b): terminal 1 must live
tmux select-window -t "$t1:b"; tmux kill-window -t hub:a; sleep 0.3
t2=$(view hub:2)
alive "$t1" || fail "opening a tab in a 2nd terminal closed the 1st terminal"
[ "$(tmux display -p -t "$t2" "#W")" = b ] || fail "hub:2 opened the wrong tab"
t3=$(view hub:Lead); alive "$t1" && alive "$t2" || fail "running lead again closed another terminal"
echo "ok: opening a tab or the lead elsewhere never closes another terminal"
# 3. --replace (mac-tab) swaps out only the older view opened for the same tab
m1=$(view --replace hub:c); m2=$(view --replace hub:c)
alive "$m1" && fail "--replace kept the old view of c"
alive "$m2" && alive "$t1" && alive "$t2" && alive "$t3" || fail "--replace closed views of other tabs"
echo "ok: --replace only replaces the same tab"
# 4. the tabs and the hub survive every view closing
for v in $(tmux list-sessions -F "#S" | grep "^view-"); do tmux kill-session -t "$v"; done
[ "$(tmux list-windows -t hub | wc -l)" = 3 ] || fail "closing views lost tabs"
echo "ok: closing every terminal keeps the hub and its tabs"
# 5. claude-tab -c reopens a tab on its last conversation
tmux kill-window -t hub:b; claude-tab ~/b -n b -c >/dev/null; sleep 0.5
tmux capture-pane -p -t hub:b | grep -q "ARGS: --continue" || fail "claude-tab -c did not pass --continue"
echo "ok: claude-tab -c continues the last conversation"
echo "ALL VIEW TESTS PASSED ($(tmux -V))"
'
