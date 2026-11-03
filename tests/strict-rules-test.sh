#!/bin/sh
# The strict-rules tools on a fresh user, in a throwaway container: link-check + send-guard, report's proof gate,
# go-live (preflight, rollback, undo), inbox-since, post-once, secret-in (macOS + Linux clipboard), lead-cap.
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/strict-rules-test.sh
set -e
if [ "$1" != --inner ]; then
  apt-get update -qq >/dev/null && apt-get install -y -qq tmux procps git jq rsync python3 chromium >/dev/null 2>&1
  useradd -m tester; cp -r /kit /tmp/kit && chown -R tester /tmp/kit
  exec su tester -s /bin/sh -c "sh /tmp/kit/tests/strict-rules-test.sh --inner"
fi
export PATH=$HOME/.local/bin:$PATH TERM=xterm-256color LK_LINK_NO_SANDBOX=1
fail() { echo "FAIL: $*"; exit 1; }
cd /tmp/kit && ./install.sh --defaults >/dev/null 2>&1
printf "LK_CLAUDE=cat\nLK_CHECK=rules\n" >> ~/.config/pierce-skill-kit/config
H=$HOME/.config/pierce-skill-kit/hooks; mkdir -p "$H"; cp hooks/send-guard.sh hooks/lead-cap.sh "$H/"

# 1. link-check: a page that loads with 200 but rejects a bad param (the 11-02 failure)
mkdir -p ~/site; cat > ~/site/claim.html <<'EOF'
<html><body><p id=m>Loading</p><script>
var ok = new URLSearchParams(location.search).get("code") === "GOOD";
document.getElementById("m").textContent = ok ? "Welcome, your order is ready" : "This link is invalid or expired";
</script></body></html>
EOF
(cd ~/site && setsid nohup python3 -m http.server 8799 >/dev/null 2>&1 < /dev/null &); sleep 2
good="http://127.0.0.1:8799/claim.html?code=GOOD"; bad="http://127.0.0.1:8799/claim.html?code=BAD"
[ "$(python3 -c "import urllib.request as u; print(u.urlopen('$bad').status)")" = 200 ] || fail "bad link should still be HTTP 200"
link-check "$good" "your order is ready" || fail "good link failed"
link-check "$bad" "your order is ready" 2>/dev/null && fail "bad link passed (a 200 is not a check)"
link-check --fresh "$good" || fail "fresh pass not found"
link-check --fresh "$bad" && fail "a failed link counts as fresh"
link-check --fresh "$good&x=1" && fail "a different URL (other params) counts as checked"
echo "ok: link-check opens the page in a real browser, catches a 200 page that rejects its params, matches exact URLs"

# 2. send-guard: no send with an unchecked link, no identical second send
sg() { sh "$H/send-guard.sh"; }
j() { printf '{"hook_event_name":"%s","tool_name":"mcp__mail__send","tool_input":{"to":"a@example.com","body":"%s"}}' "$1" "$2"; }
j PreToolUse "Here you go: $good." | sg | grep -q deny && fail "send with a checked link was blocked"
j PreToolUse "Here you go: $bad" | sg | grep -q "no recent link-check pass" || fail "send with a failed link not blocked"
j PreToolUse "Here: http://127.0.0.1:8799/other" | sg | grep -q "no recent link-check pass" || fail "send with an unchecked link not blocked"
j PostToolUse "Here you go: $good." | sg
j PreToolUse "Here you go: $good." | sg | grep -q "already sent" || fail "identical second send not blocked"
j PreToolUse "Follow-up: $good" | sg | grep -q deny && fail "a different message was blocked"
echo "ok: send-guard refuses unchecked/failed links and an identical second send"

# 3. report: done needs proof that exists
lead -d >/dev/null 2>&1 || true
set +e; report demo "done" "all done" 2>/dev/null; r=$?; set -e; [ $r = 3 ] || fail "done without proof not refused with exit 3"
report demo "done" "all done" /no/such 2>/dev/null && fail "done with a missing proof file accepted"
grep -q "demo" ~/.pierce-skill-kit/reports.tsv 2>/dev/null && fail "refused done was logged"
echo proof > /tmp/p.log; report demo "done" "tests green" /tmp/p.log >/dev/null || fail "done with proof refused"
report demo "done" "preview up" "$good" >/dev/null || fail "done with a link refused"
report demo progress "half way" >/dev/null || fail "progress needs no proof"
echo "ok: report refuses done without an existing proof file or link"

# 4. go-live: preflight before live, auto-rollback, undo stamp
mkdir -p ~/live ~/v2; echo v1 > ~/live/index.html; echo v2 > ~/v2/index.html
go-live --live ~/live --new ~/v2 --needs ~/v2/sitemap.xml --then "cp $HOME/v2/sitemap.xml ." 2>/tmp/e && fail "missing input passed preflight"
grep -q "PREFLIGHT FAILED, live not touched" /tmp/e && grep -q "sitemap.xml" /tmp/e || fail "preflight message: $(cat /tmp/e)"
grep -qx v1 ~/live/index.html || fail "preflight failure touched live"
go-live --live ~/live --new ~/v2 --then "no-such-tool --x" 2>/dev/null && fail "missing command passed preflight"
go-live --live ~/live --new ~/v2 --then "sh -c 'exit 1'" --verify "grep -q v1 index.html" 2>/tmp/e && fail "failing step passed"
grep -qx v1 ~/live/index.html || fail "failed release not rolled back"
grep -q "old version verifies again" /tmp/e || fail "rollback not verified: $(cat /tmp/e)"
out=$(go-live --live ~/live --new ~/v2 --then "touch built.txt" --verify "grep -q v2 index.html") || fail "good release failed"
grep -qx v2 ~/live/index.html && [ -f ~/live/built.txt ] || fail "release not applied"
stamp=$(echo "$out" | sed -n "s/.*go-live --undo //p"); [ -n "$stamp" ] || fail "no undo stamp: $out"
[ "$(cat ~/.pierce-skill-kit/go-live/$stamp/UNDO)" = "go-live --undo $stamp" ] || fail "UNDO file"
go-live --undo "$stamp" >/dev/null; grep -qx v1 ~/live/index.html && [ ! -f ~/live/built.txt ] || fail "undo did not restore v1 exactly"
echo "ok: go-live checks every input before touching live, rolls back a failed step, leaves a working undo stamp"

# 5. inbox-since: by time, never by tail; a cut-off page is caught
t=$(printf "1000.1\tvendor: hi\n1000.2\tus: ok\n1000.3\tvendor: invoice attached\n")
[ "$(printf "%s\n" "$t" | inbox-since vendor | wc -l)" = 3 ] || fail "first read"
[ -z "$(printf "%s\n" "$t" | inbox-since vendor)" ] || fail "re-read showed old messages"
printf "%s\n1000.4\tvendor: reply you must not miss\n" "$t" | inbox-since vendor | grep -q "must not miss" || fail "new message missed"
set +e; printf "1000.6\tb\n1000.7\tc\n" | inbox-since vendor --page 2 >/dev/null 2>&1; r=$?
printf "no timestamp here\n" | inbox-since vendor >/dev/null 2>&1; r2=$?; set -e
[ $r = 3 ] || fail "a full page of only-new messages (gap) not flagged: exit $r"
[ $r2 = 2 ] || fail "line without timestamp not refused: exit $r2"
echo "ok: inbox-since reads by timestamp, never repeats, flags a cut-off page and lines without a time"

# 6. post-once: one post per message, verified by count
: > /tmp/chan; post() { echo "$1" >> /tmp/chan; }
cnt="grep -c deploy-notice /tmp/chan || true"
post-once --count "$cnt" "chan:deploy-notice" -- sh -c "echo deploy-notice >> /tmp/chan" >/dev/null || fail "first post"
post-once "chan:deploy-notice" -- sh -c "echo deploy-notice >> /tmp/chan" 2>/dev/null && fail "second identical post allowed"
post-once --count "$cnt" "chan:deploy-notice v2" -- sh -c "echo deploy-notice >> /tmp/chan" 2>/dev/null && fail "post the target already shows was allowed"
[ "$(grep -c deploy-notice /tmp/chan)" = 1 ] || fail "channel has $(grep -c deploy-notice /tmp/chan) posts"
set +e; post-once --count "grep -c twice /tmp/chan || true" "chan:twice" -- sh -c "echo twice >> /tmp/chan; echo twice >> /tmp/chan" 2>/dev/null; r=$?; set -e
[ $r = 4 ] || fail "a double post inside the command not caught: exit $r"
echo "ok: post-once refuses a repeat, checks the target first, and catches a double post"

# 7. secret-in: from the clipboard (macOS pbpaste, Linux xclip) into the secrets folder, value never printed
mkdir -p ~/stub; printf '#!/bin/sh\necho "  demo-key-PASTED-123  "\n' > ~/stub/pbpaste; printf '#!/bin/sh\ncat >/dev/null; touch /tmp/cleared\n' > ~/stub/pbcopy
chmod +x ~/stub/*; out=$(PATH=~/stub:$PATH secret-in demo.env DEMO_KEY)
echo "$out" | grep -q PASTED && fail "secret-in printed the value"
[ "$(cat ~/.secrets/demo.env)" = "DEMO_KEY=demo-key-PASTED-123" ] || fail "secret not saved: $(cat ~/.secrets/demo.env)"
[ "$(stat -c %a ~/.secrets/demo.env)" = 600 ] && [ "$(stat -c %a ~/.secrets)" = 700 ] || fail "secret permissions"
[ -f /tmp/cleared ] || fail "clipboard not cleared"
rm ~/stub/pbpaste ~/stub/pbcopy; printf '#!/bin/sh\n[ "$1" = -o ] && echo linux-key-456; cat >/dev/null 2>&1; exit 0\n' > ~/stub/xclip; chmod +x ~/stub/xclip
PATH=~/stub:$PATH secret-in lin.key | grep -q "saved .*lin.key (13 characters" || fail "xclip path"
echo "piped-789" | secret-in --prompt p.key 2>/dev/null | grep -q saved && [ "$(cat ~/.secrets/p.key)" = piped-789 ] || fail "--prompt path"
secret-in ../x 2>/dev/null && fail "path in file name allowed"
echo "ok: secret-in saves clipboard/prompt input 600 in a 700 folder, prints only the path, clears the clipboard"

# 8. lead-cap: the lead's hands-on commands are capped per turn; its own tools and project tabs are not
tmux has-session -t hub 2>/dev/null || tmux new-session -d -s hub -n Lead
tmux list-windows -t hub -F "#W" | grep -qx Lead || tmux new-window -d -t hub: -n Lead
tmux new-window -d -t hub: -n alpha
lp=$(tmux display -p -t hub:Lead "#{pane_id}"); ap=$(tmux display -p -t hub:alpha "#{pane_id}")
cap() { printf '{"hook_event_name":"%s","session_id":"s1","tool_input":{"command":"%s"}}' "$2" "$3" | TMUX_PANE=$1 sh "$H/lead-cap.sh" 2>/dev/null; }
cap "$lp" UserPromptSubmit ""
for i in 1 2 3 4 5 6; do cap "$lp" PreToolUse "npm run build" || fail "command $i blocked under the cap"; done
cap "$lp" PreToolUse "report x progress y" || fail "lead tool counted against the cap"
cap "$lp" PreToolUse "git status" || fail "read-only git counted"
cap "$lp" PreToolUse "npm run build" && fail "7th hands-on command allowed"
cap "$ap" PreToolUse "npm run build" || fail "project tab was capped"
cap "$lp" UserPromptSubmit ""; cap "$lp" PreToolUse "npm run build" || fail "count not reset on a new turn"
echo "ok: lead-cap blocks the 7th hands-on command in a turn, only in the lead window, resets each turn"
echo "strict rules test passed"
