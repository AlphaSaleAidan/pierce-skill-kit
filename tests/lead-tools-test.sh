#!/bin/sh
# tab-sweep, report-check, the job watchdog, lead-say and the dtach lead on a fresh user, in a throwaway container:
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/lead-tools-test.sh
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq tmux procps git iproute2 netcat-openbsd jq dtach >/dev/null 2>&1
useradd -m tester; cp -r /kit /tmp/kit && chown -R tester /tmp/kit
su tester -s /bin/sh -c '
set -e
export PATH=$HOME/.local/bin:$PATH TERM=xterm-256color
fail() { echo "FAIL: $*"; tmux capture-pane -p -t hub:Lead -S -30 | tail -15; exit 1; }
cd /tmp/kit && ./install.sh --defaults >/dev/null 2>&1
printf "LK_CLAUDE=cat\nLK_CHECK=rules\nLK_SWEEP_IDLE_MIN=0\nLK_JOB_RETRY_MIN=0\nLK_JOB_LIMIT_PAD_S=0\n" >> ~/.config/pierce-skill-kit/config
git config --global user.email t@t; git config --global user.name t
for p in clean dirty asking serving fresh; do mkdir -p ~/$p; git -C ~/$p init -q; git -C ~/$p commit -q --allow-empty -m init; done
echo wip > ~/dirty/notes.txt
lead -d; for p in clean dirty asking fresh; do claude-tab ~/$p -n $p >/dev/null; done
tmux new-window -d -t hub: -n serving -c ~/serving "nc -l -p 8765"
rep() { TMUX_PANE=$(tmux display -p -t "hub:$1" "#{pane_id}") report "$@" >/dev/null; }
# report-check rides on every report
rep clean done "shipped the fix, commit 3f9a2c1" /etc/hostname; rep dirty done "all done"; rep asking needs-human "A or B?"
rep serving done "preview up, commit 3f9a2c1" /etc/hostname
sleep 1; L=$(tmux capture-pane -p -t hub:Lead -S -40 | tr -d "\n")
echo "$L" | grep -q "shipped the fix, commit 3f9a2c1 | /etc/hostname {check rules: ok}" || fail "no ok check on a proven report"
echo "$L" | grep -q "all done {check rules: no proof for done: verify before telling the human}" || fail "thin done not flagged"
[ "$(grep -c rules ~/.pierce-skill-kit/report-checks.tsv)" = 4 ] || fail "checks not logged"
echo "ok: every report carries a check; a done without proof is flagged; checks are logged"
# a past conversation for the clean tab, so the retired line can resume it
mkdir -p ~/.claude/projects/$(printf %s "$HOME/clean" | sed "s/[^A-Za-z0-9]/-/g"); touch ~/.claude/projects/$(printf %s "$HOME/clean" | sed "s/[^A-Za-z0-9]/-/g")/abc-123.jsonl
sleep 1; out=$(tab-sweep --dry-run)
echo "$out" | grep -q "would close clean" || fail "dry run: clean tab not closable: $out"
[ "$(tmux list-windows -t hub | wc -l)" = 6 ] || fail "dry run closed something"
echo "ok: --dry-run only says what it would do"
out=$(tab-sweep); echo "$out" | sed "s/^/    /"
echo "$out" | grep -q "^closed clean (reopen: claude-tab $HOME/clean -n clean -r abc-123)" || fail "clean tab not closed with its resume id"
echo "$out" | grep -q "FLAG   dirty: reported done but 1 uncommitted" || fail "dirty tab not flagged"
echo "$out" | grep -q "FLAG   serving: reported done but still serving .*8765" || fail "serving tab not flagged"
echo "$out" | grep -q "open   asking: last report is needs-human" || fail "needs-human tab not left open"
echo "$out" | grep -q "open   fresh: last report is none" || fail "unreported tab not left open"
tmux list-windows -t hub -F "#W" | grep -qx clean && fail "clean window still there"
[ "$(tmux list-windows -t hub | wc -l)" = 5 ] || fail "closed more than the clean tab"
grep -q "clean ($HOME/clean): reopen with .claude-tab $HOME/clean -n clean -r abc-123." ~/.pierce-skill-kit/retired-tabs.md || fail "retired-tabs line"
sed -i "s/^LK_SWEEP_IDLE_MIN=0/LK_SWEEP_IDLE_MIN=999/" ~/.config/pierce-skill-kit/config
tab-sweep | grep -q "FLAG   serving: reported done but busy" || fail "recently busy tab not held"
echo "ok: tab-sweep closes only a done, saved, quiet tab; flags dirty/serving/busy ones; logs how to reopen"
# job watchdog
job run ok1 -- sh -c "echo hi" >/dev/null
job run bad -t 2 -- sh -c "echo boom; exit 4" >/dev/null
job run lim -- sh -c "if [ -f /tmp/lim-once ]; then echo second run ok; else touch /tmp/lim-once; echo \"Claude AI usage limit reached|\$((\$(date +%s) + 2))\"; exit 1; fi" >/dev/null
job run long -- sleep 300 >/dev/null
sleep 6
job list | sed "s/^/    /"
[ "$(cat ~/.pierce-skill-kit/jobs/ok1/state)" = done ] || fail "ok1 not done"
[ "$(cat ~/.pierce-skill-kit/jobs/bad/state)" = failed ] && [ "$(cat ~/.pierce-skill-kit/jobs/bad/tries)" = 2 ] || fail "bad: not failed after 2 tries"
[ "$(cat ~/.pierce-skill-kit/jobs/lim/state)" = done ] && grep -q "second run ok" ~/.pierce-skill-kit/jobs/lim/log || fail "lim: not relaunched after the usage-limit reset"
L=$(tmux capture-pane -p -t hub:Lead -S -80 | tr -d "\n")
echo "$L" | grep -q "job bad: exit 4, gave up after 2 tries" || fail "bad failure not reported"
echo "$L" | grep -q "job lim: hit a usage limit (exit 1); relaunching at" || fail "usage limit not reported"
echo "$L" | grep -q "job ok1: finished" || fail "finish not reported"
kill -9 "$(cat ~/.pierce-skill-kit/jobs/long/pid)"; tab-watch; sleep 1
[ "$(cat ~/.pierce-skill-kit/jobs/long/state)" = died ] || fail "dead watchdog not noticed"
tmux capture-pane -p -t hub:Lead -S -80 | tr -d "\n" | grep -q "job long: its watchdog died" || fail "dead watchdog not reported"
echo "ok: jobs relaunch after a failure and after a usage-limit reset, give up after N tries, and every step (and a killed watchdog) reaches the lead"
lead-daily | grep -q "dirty: 1 of 1 reports were \"done\" without solid proof" || fail "digest lacks the check summary"
echo "ok: the daily digest lists tabs with thin done reports"
# lead-say: never types into a login prompt, a half-typed message, or over a recent keypress
cfg=~/.config/pierce-skill-kit/config; cp $cfg /tmp/login.cfg
printf "LK_LEAD_WINDOW=login\nLK_SAY_WAIT_MIN=0\n" >> /tmp/login.cfg
tmux new-window -d -t hub: -n login "printf \"Paste code here if prompted > \"; cat"
sleep 1
out=$(LK_CONFIG=/tmp/login.cfg lead-say "ALERT must not land in the code box"); echo "    $out"
echo "$out" | grep -q "^queued: a prompt is on screen" || fail "lead-say did not see the login prompt: $out"
sleep 1
tmux capture-pane -p -t hub:login | grep -q ALERT && fail "lead-say typed into the login prompt"
grep -q "UNDELIVERED: ALERT must not land in the code box" ~/.pierce-skill-kit/undelivered.log || fail "queued line not logged as undelivered"
tmux kill-window -t hub:login
tmux new-window -d -t hub: -n login "printf \"\342\235\257 half a messa\"; cat"
sleep 1
LK_CONFIG=/tmp/login.cfg lead-say --check | grep -q "busy: the human is typing" || fail "half-typed message not seen"
tmux kill-window -t hub:login
lead-say --check >/dev/null && fail "idle lead reported busy: $(lead-say --check)"
touch ~/.pierce-skill-kit/lead.keys
lead-say --check | grep -q "busy: a keypress in the last 20s" || fail "recent keypress (leader keys file) not seen"
touch -d "1 hour ago" ~/.pierce-skill-kit/lead.keys
[ "$(lead-say "free now, goes straight in")" = delivered ] || fail "free lead: not delivered"
sleep 1; tmux capture-pane -p -t hub:Lead -S -20 | grep -q "free now, goes straight in" || fail "delivered line not in the lead"
echo "ok: lead-say holds back for a login prompt, a half-typed message and a recent keypress; delivers when free"
# dtach lead: the Claude lives under dtach, the tmux window is a viewer that lead-say still types into
cp $cfg /tmp/dtach.cfg; printf "LK_HUB=hub2\nLK_LEAD_DTACH=1\n" >> /tmp/dtach.cfg
LK_CONFIG=/tmp/dtach.cfg lead -d >/dev/null; sleep 1
[ -S ~/.pierce-skill-kit/lead.sock ] || fail "no dtach socket for the lead"
[ "$(LK_CONFIG=/tmp/dtach.cfg lead-say "through dtach")" = delivered ] || fail "dtach lead: not delivered"
sleep 1; tmux capture-pane -p -t hub2:Lead | grep -q "through dtach" || fail "dtach lead did not get the line"
tmux kill-session -t hub2
echo "ok: LK_LEAD_DTACH=1 runs the lead under dtach; lead-say still reaches it"
echo "ALL LEAD TOOLS TESTS PASSED"
'
