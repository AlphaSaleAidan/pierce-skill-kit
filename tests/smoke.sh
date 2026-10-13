#!/bin/sh
# Fresh-install smoke test. Run in a throwaway container (it installs packages and adds a user):
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/smoke.sh
# A stand-in for Claude (`cat`) runs in each window so the test needs no login.
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq tmux procps >/dev/null
useradd -m tester
cp -r /kit /tmp/kit && chown -R tester /tmp/kit
su tester -s /bin/sh -c '
set -e
export PATH=$HOME/.local/bin:$PATH
fail() { echo "FAIL: $*"; tmux capture-pane -p -t hub:Lead | tail -15; exit 1; }
cd /tmp/kit && ./install.sh --yes
echo "LK_CLAUDE=cat" >> ~/.config/pierce-skill-kit/config
mkdir -p ~/alpha ~/beta
test -f ~/.claude/skills/terminal-lead/SKILL.md && test -f ~/.claude/skills/project-tab/SKILL.md || fail "skills not installed"
grep -q "BEGIN pierce-skill-kit rules" ~/.claude/CLAUDE.md || fail "rules not appended"
[ "$(ls ~/.claude/skills | wc -l)" = "$(ls /tmp/kit/skills | wc -l)" ] && test -f ~/.claude/skills/phone-qa/SKILL.md && [ "$(find ~/.claude/skills/phone-qa -type f | wc -l)" -gt 1 ] || fail "extra skills not installed whole"
./install.sh --yes >/dev/null; [ "$(grep -c "BEGIN pierce-skill-kit rules" ~/.claude/CLAUDE.md)" = 1 ] || fail "re-install duplicated the rules"
lead -d
claude-tab ~/alpha -n alpha
claude-tab ~/beta -n beta
set +e; claude-tab ~/alpha -n alpha2 2>/dev/null; rc=$?; set -e
[ $rc = 3 ] || fail "duplicate folder was not refused (rc=$rc)"
[ "$(tmux list-windows -t hub | wc -l)" = 3 ] || fail "expected 3 windows (lead + 2 tabs)"
echo "ok: lead + 2 tabs, duplicate refused"
# a report from inside tab alpha
TMUX_PANE=$(tmux display -p -t hub:alpha "#{pane_id}") report alpha done "smoke report" /tmp/proof.txt
sleep 1
tmux capture-pane -p -t hub:Lead | grep -q "\[REPORT done\] alpha (alpha): smoke report | /tmp/proof.txt" || fail "report did not land in the lead"
grep -q "	alpha	done	smoke report	/tmp/proof.txt	alpha$" ~/.pierce-skill-kit/reports.tsv || fail "report not logged"
echo "ok: report landed in the lead and the log"
# watchdog: baseline + two unchanged checks -> beta (never reported) flagged, alpha (reported just now) not
tab-watch; tab-watch; tab-watch; sleep 1
lead_pane=$(tmux capture-pane -p -t hub:Lead -S -50)
echo "$lead_pane" | grep -q "\[WATCH\] tab .beta." || fail "idle tab beta not flagged"
echo "$lead_pane" | grep -q "\[WATCH\] tab .alpha." && fail "alpha flagged despite a fresh report"
n1=$(tmux capture-pane -p -t hub:Lead -S -80 | grep -c "WATCH\] tab .beta.")
tab-watch; sleep 1
[ "$(tmux capture-pane -p -t hub:Lead -S -80 | grep -c "WATCH\] tab .beta.")" = "$n1" ] || fail "beta flagged twice"
echo "ok: tab-watch flagged idle beta once, skipped alpha"
# needs-human tabs are waiting, not stuck
tmux kill-window -t hub:beta; claude-tab ~/beta -n gamma >/dev/null
TMUX_PANE=$(tmux display -p -t hub:gamma "#{pane_id}") report gamma needs-human "pick A or B" >/dev/null
sed -i "s/^\([^\t]*\)\tgamma/2000-01-01T00:00Z\tgamma/" ~/.pierce-skill-kit/reports.tsv
tab-watch; tab-watch; tab-watch; sleep 1
tmux capture-pane -p -t hub:Lead -S -80 | grep -q "WATCH\] tab .gamma." && fail "needs-human tab was flagged"
echo "ok: needs-human tab not flagged"
order add alpha "fix it" >/dev/null; order done 1 "commit abc" >/dev/null; order list all | grep -q "done" || fail "order ledger"
[ "$(heavy echo heavy-ok)" = heavy-ok ] || fail "heavy"
lead-daily | grep -q "smoke report" || fail "lead-daily missing the report"
echo "ok: order, heavy, lead-daily"
echo "ALL SMOKE TESTS PASSED"
'
