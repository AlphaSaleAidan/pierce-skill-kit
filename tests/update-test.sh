#!/bin/sh
# tmux copy behaviour + `lead update`, in a throwaway container:
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/update-test.sh
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq tmux git procps jq >/dev/null
fail() { echo "FAIL: $*"; exit 1; }
cp -r /kit /tmp/up && cd /tmp/up && rm -rf .git && git init -q && git add -A && git -c user.name=t -c user.email=t@example.com commit -qm v1
git clone -q /tmp/up $HOME/kit && cd $HOME/kit && sh install.sh --yes >/dev/null
export PATH=$HOME/.local/bin:$PATH
# --- copy: drag-end copies but stays in scroll mode (no jump); borders are grey
tmux -f ~/.tmux.conf new -d -s t -x 120 -y 30 'seq 1 500; sleep 60'; sleep 1
tmux list-keys -T copy-mode | grep -qE 'MouseDragEnd1Pane +send-keys -X copy-selection-no-clear' || fail "drag-end binding"
tmux list-keys -T copy-mode | grep -qE 'MouseDown1Pane +select-pane .*clear-selection' || fail "click binding"
[ "$(tmux show -gv pane-active-border-style)" = "fg=colour238" ] || fail "active border style"
[ "$(tmux show -gv mode-style)" = "bg=colour24,fg=colour255" ] || fail "mode-style"
tmux copy-mode -t t; tmux send -t t -X -N 5 scroll-up; tmux send -t t -X begin-selection; tmux send -t t -X -N 3 cursor-down
tmux send -t t -X copy-selection-no-clear
[ "$(tmux display -p -t t '#{pane_in_mode}')" = 1 ] || fail "copy left scroll mode (would jump)"
[ -n "$(tmux show-buffer 2>/dev/null)" ] || fail "nothing copied"
echo "ok: copy keeps scroll mode, buffer filled, borders grey, no green"
# --- lead update: a new commit upstream lands on the next update, tmux reloads live
cd /tmp/up && sed -i 's/fg=colour238/fg=colour240/' tmux/pierce-skill-kit.tmux.conf && echo "# v2 marker" >> skills/project-tab/SKILL.md && \
  git -c user.name=t -c user.email=t@example.com commit -qam v2
out=$(lead update) || fail "lead update"; echo "$out" | grep -q "updated .* -> " || fail "no update reported: $out"
[ "$(tmux show -gv pane-active-border-style)" = "fg=colour240" ] || fail "tmux not reloaded live"
grep -q "v2 marker" ~/.claude/skills/project-tab/SKILL.md || fail "skill not refreshed"
[ "$(lead update)" = "already up to date ($(git -C $HOME/kit rev-parse --short HEAD))" ] || fail "second update"
crontab -l 2>/dev/null | grep -q 'pierce-skill-kit auto-update' || echo "note: no crontab in this image (auto-update line not testable here)"
echo "ok: lead update pulled v2, refreshed the skill, reloaded tmux live; second run is a no-op"
echo "ALL UPDATE TESTS PASSED"
