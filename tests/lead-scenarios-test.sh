#!/bin/sh
# The lead's operating manual, scenario by scenario, on a fresh user (tools side; tests/lead-eval/ checks the model):
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/lead-scenarios-test.sh
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq tmux procps git iproute2 jq >/dev/null 2>&1
useradd -m tester; cp -r /kit /tmp/kit && chown -R tester /tmp/kit
su tester -s /bin/sh -c '
set -e
export PATH=$HOME/.local/bin:$PATH TERM=xterm-256color
fail() { echo "FAIL: $*"; exit 1; }
M=/tmp/kit/skills/terminal-lead/SKILL.md
# 0. the manual itself: short enough to follow, and it covers every rule the brief asked for
[ "$(wc -l < $M)" -le 250 ] || fail "manual is over 250 lines"
for rule in "lead-round" "/loop" "lead-recall" "order add" "order done" "OLD\|24 h" "{check" "tab-sweep" "by name, never by number" \
  "never the human.s approval" "exact command" "BOLD NEXT" "Answer first" "job run" "lead never builds" "heartbeat"; do
  grep -q "$rule" $M || fail "manual lacks: $rule"; done
echo "ok: the manual is under 250 lines and covers loop, recall, orders, checks, sweep, names, approvals, ambition, style"
# 1. install: the lead gets its own folder and instructions, never in HOME
cd /tmp/kit && ./install.sh --defaults >/dev/null 2>&1
printf "LK_CLAUDE=cat\nLK_CHECK=rules\nLK_SWEEP_IDLE_MIN=0\n" >> ~/.config/pierce-skill-kit/config
grep -q "BEGIN pierce-skill-kit lead" ~/lead/CLAUDE.md || fail "no lead CLAUDE.md in ~/lead"
[ ! -e ~/CLAUDE.md ] || fail "wrote a CLAUDE.md into HOME"
echo "# my own note" >> ~/lead/CLAUDE.md; ./install.sh --update >/dev/null 2>&1
[ "$(grep -c "BEGIN pierce-skill-kit lead" ~/lead/CLAUDE.md)" = 1 ] && grep -q "my own note" ~/lead/CLAUDE.md || fail "update duplicated the block or lost own lines"
out=$(LK_CONFIG=/dev/null; printf "LK_LEAD_DIR=\"\$HOME\"\n" > /tmp/home.cfg; cp ~/.config/pierce-skill-kit/config /tmp/keep.cfg; cp /tmp/home.cfg ~/.config/pierce-skill-kit/config; ./install.sh --update 2>&1; cp /tmp/keep.cfg ~/.config/pierce-skill-kit/config)
echo "$out" | grep -q "lead   -> skipped: the lead.s folder is your home folder" && [ ! -e ~/CLAUDE.md ] || fail "LK_LEAD_DIR=HOME was not refused"
echo "ok: lead instructions land in ~/lead/CLAUDE.md, refresh in place, and never in HOME"
# 2. the human asks something already answered
mkdir -p ~/.pierce-skill-kit; printf "2026-10-10 acme: landing page domain is acme-shop.com (human, verbatim: \"use acme-shop.com\")\n" >> ~/.pierce-skill-kit/decisions.md
lead-recall Domain LANDING | grep -q "decisions.md:1: .*acme-shop.com" || fail "lead-recall missed a recorded decision"
lead-recall nothing-like-this >/dev/null 2>&1 && fail "lead-recall invented a match"
echo "ok: lead-recall finds an earlier decision (any word order/case) and says when there is none"
# 3. tabs, orders, reports
mkdir -p ~/acme ~/beta ~/gamma; for p in acme beta gamma; do git -C ~/$p init -q; done
lead -d; for p in acme beta gamma; do claude-tab ~/$p -n $p >/dev/null; done
order add acme "landing page live" >/dev/null; order add beta "fix login" >/dev/null; order wait 2 "human: which provider?" >/dev/null
sed -i "2s/\t20[0-9-]*T[0-9:]*Z\t/\t2026-01-01T00:00Z\t/" ~/.pierce-skill-kit/orders.tsv
order list | grep -q "^#1 .* OLD .*landing page live" || fail "a 24h+ order is not marked OLD"
TMUX_PANE=$(tmux display -p -t hub:acme "#{pane_id}") report acme progress "hero done. BOLD NEXT: sell the template as a kit, first step a demo page" >/dev/null
d=$(lead-daily)
echo "$d" | sed -n "/Waiting on you/,/Open orders/p" | grep -q "landing page live" && echo "$d" | sed -n "/Waiting on you/,/Open orders/p" | grep -q "fix login" || fail "digest does not remind about OLD and waiting orders"
echo "$d" | grep -q "^- acme: sell the template as a kit" || fail "digest does not collect BOLD NEXT ideas"
echo "ok: orders show their age; the digest reminds about old and waiting asks and collects BOLD NEXT ideas"
# 4. a tab closes and numbers shift: everything by name still hits the right tab
tmux kill-window -t hub:acme; printf "x" > /tmp/brief.md
brief-send gamma /tmp/brief.md >/dev/null; sleep 0.5
tmux capture-pane -p -t hub:gamma | tr -d "\n" | grep -q "read /tmp/brief.md" || fail "brief by name missed gamma after renumbering"
tmux capture-pane -p -t hub:beta | grep -q "read /tmp/brief.md" && fail "brief landed in beta (the old number)"
echo "ok: after a tab closes, briefs by name still reach the right tab"
# 5. lead-round shows the red lines a round must act on
tmux send-keys -t hub:beta -l "Do you want to proceed? (y/n)"; tmux send-keys -t hub:beta Enter
echo hi > /tmp/hb.log; touch -d "3 hours ago" /tmp/hb.log; echo "LK_HEARTBEATS=\"/tmp/hb.log:60 /tmp/missing.log:60\"" >> ~/.config/pierce-skill-kit/config
job run broken -t 1 -- sh -c "exit 3" >/dev/null; sleep 2
TMUX_PANE=$(tmux display -p -t hub:gamma "#{pane_id}") report gamma done "shipped, commit 1234567" >/dev/null; echo junk > ~/gamma/wip.txt
r=$(lead-round); echo "$r" | sed "s/^/    /"
echo "$r" | grep -q "^! beta: .*WAITING ON A PROMPT" || fail "round missed a tab stuck on a prompt"
echo "$r" | grep -q "^! /tmp/hb.log: [0-9]* min old (max 60)" && echo "$r" | grep -q "^! /tmp/missing.log: missing" || fail "round missed a stale/missing heartbeat"
echo "$r" | grep -q "^! broken .*failed" || fail "round missed a failed job"
echo "$r" | grep -q "^! FLAG   gamma: reported done but 1 uncommitted" || fail "round missed done-but-unsaved work"
echo "$r" | grep -q "OLD" || fail "round does not show old orders"
echo "ok: lead-round puts every red item (prompt, heartbeat, job, unsaved done, old order) on one screen"
echo "ALL LEAD SCENARIO TESTS PASSED"
'
