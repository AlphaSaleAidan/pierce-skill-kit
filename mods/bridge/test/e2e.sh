#!/bin/sh
# End-to-end test of the bridge, entirely in throwaway docker containers on a private docker network:
#   vps   - debian slim + sshd + tmux + the kit (LK_CLAUDE=cat stands in for Claude), running `lead -d`
#   local - node + openssh-client: the Mac/Linux side (bridge + mcp.mjs)
#   win   - mcr.microsoft.com/powershell + openssh-client: bridge.ps1 (PowerShell 7 on Linux, not real Windows)
# Run from anywhere:  sh mods/bridge/test/e2e.sh        (needs docker and network access for apt-get)
# shellcheck disable=SC2088  # "~/..." expands inside the containers
set -u
KIT=$(cd "$(dirname "$0")/../../.." && pwd)
N=bridge-e2e-$$
D="nice -n 15 docker"
fails=0
cleanup() { $D rm -f "$N-vps" "$N-local" "$N-win" >/dev/null 2>&1; $D network rm "$N" >/dev/null 2>&1; }
trap cleanup EXIT INT TERM
ok() { echo "PASS: $*"; }
no() { echo "FAIL: $*"; fails=$((fails + 1)); }
t() { d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
V() { $D exec -u tester -e HOME=/home/tester -w /home/tester "$N-vps" sh -c "$1"; }   # as the kit user on the vps
L() { $D exec -e PATH=/root/pierce-bridge/bin:/usr/local/bin:/usr/bin:/bin "$N-local" sh -c "$1"; }
W() { $D exec "$N-win" sh -c "$1"; }
VL() { V "$1" && L "$2"; }   # VL <vps check> <local check>
pane() { V 'tmux capture-pane -p -J -t hub:Lead -S -200'; }
SH=/home/tester/.pierce-skill-kit/shared; LC=/root/pierce-bridge/context

$D network create "$N" >/dev/null
$D run -d --init --name "$N-vps" --network "$N" --network-alias vps -v "$KIT:/kit:ro" debian:stable-slim sleep infinity >/dev/null
$D run -d --init --name "$N-local" --network "$N" -v "$KIT:/kit:ro" node:22-slim sleep infinity >/dev/null
$D run -d --init --name "$N-win" --network "$N" -v "$KIT:/kit:ro" mcr.microsoft.com/powershell:latest sleep infinity >/dev/null
echo "== installing packages (containers only)"
$D exec "$N-vps" sh -c 'apt-get update -qq && apt-get install -y -qq openssh-server tmux procps >/dev/null' >/dev/null 2>&1 &
$D exec "$N-local" sh -c 'apt-get update -qq && apt-get install -y -qq openssh-client xz-utils bzip2 >/dev/null' >/dev/null 2>&1 &
$D exec "$N-win" sh -c 'apt-get update -qq && apt-get install -y -qq openssh-client >/dev/null' >/dev/null 2>&1 &
wait
$D exec "$N-vps" sh -c 'useradd -m -s /bin/sh tester && usermod -p "*" tester && mkdir -p /run/sshd && ssh-keygen -A >/dev/null && /usr/sbin/sshd -o PerSourcePenalties=no -o MaxStartups=100:30:200' \
  || { echo "FAIL: vps sshd"; exit 1; }
$D exec "$N-vps" sh -c 'cp -r /kit /tmp/kit && chown -R tester /tmp/kit'
V 'cd /tmp/kit && ./install.sh --no >/dev/null && echo LK_CLAUDE=cat >> ~/.config/pierce-skill-kit/config && ~/.local/bin/lead -d' >/dev/null \
  || { echo "FAIL: kit install / lead -d on vps"; exit 1; }
addkey() { $D exec "$1" sh -c 'ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519 </dev/null >/dev/null; cat /root/.ssh/id_ed25519.pub' \
  | $D exec -i "$N-vps" sh -c 'd=/home/tester/.ssh; mkdir -p $d && cat >> $d/authorized_keys && chown -R tester $d && chmod 700 $d && chmod 600 $d/authorized_keys'; }
$D exec "$N-local" mkdir -p /root/.ssh; $D exec "$N-win" mkdir -p /root/.ssh
addkey "$N-local"; addkey "$N-win"

echo "== setup"
out=$(L '/kit/mods/bridge/bridge setup tester@vps --name laptop' 2>&1)
t "setup prints the MCP add command (claude not installed here)" sh -c 'echo "$1" | grep -qF "claude mcp add -s user bridge -- node /root/pierce-bridge/bin/mcp.mjs"' _ "$out"
t "setup installed bridge-serve on the vps" V 'test -x ~/.local/bin/bridge-serve && test -x ~/.local/bin/bridge'
t "setup wrote the local config" L 'grep -qx BRIDGE_VPS=tester@vps ~/pierce-bridge/config && grep -qx BRIDGE_NAME=laptop ~/pierce-bridge/config'
echo "$out" | grep -q 'lead window hub:Lead running' && ok "setup ping sees the lead window" || no "setup ping sees the lead window ($out)"

echo "== messaging"
L 'bridge send "hello lead, laptop here"' >/dev/null 2>&1; sleep 1
t "send lands in the VPS lead pane" sh -c 'echo "$1" | grep -qF "[BRIDGE from laptop] hello lead, laptop here"' _ "$(pane)"
t "send is logged on the vps" V 'grep -q "	laptop	hello lead, laptop here" ~/.pierce-skill-kit/bridge/messages.tsv'
V '~/.local/bin/bridge reply "hi laptop, got it"' >/dev/null
t "reply queues cleanly on the vps" V "~/.local/bin/bridge reply \"second note\" | grep -q queued"
t "reply reaches the local inbox" sh -c 'echo "$1" | grep -q "hi laptop, got it"' _ "$(L 'bridge inbox')"
t "inbox marks read (second call: nothing new)" sh -c 'echo "$1" | grep -q "no new messages"' _ "$(L 'bridge inbox')"
t "inbox --all still shows it" sh -c 'echo "$1" | grep -q "hi laptop, got it"' _ "$(L 'bridge inbox --all')"

echo "== messaging edge cases"
t "inbox again with nothing new stays quiet" sh -c 'echo "$1" | grep -q "no new messages" && ! echo "$1" | grep -q "got it"' _ "$(L 'bridge inbox')"
t "inbox --all shows each message once (no duplicates after repeated fetches)" sh -c '[ "$(echo "$1" | grep -c "hi laptop, got it")" = 1 ]' _ "$(L 'bridge inbox --all')"
t "inbox --all does not mark anything unread" sh -c 'echo "$1" | grep -q "no new messages"' _ "$(L 'bridge inbox')"
U='héllo wörld 日本語 🚀✅ ñandú'
L "bridge send '$U'" >/dev/null 2>&1; sleep 1
t "unicode + emoji send arrives intact on the vps log" V "grep -qF '$U' ~/.pierce-skill-kit/bridge/messages.tsv"
t "unicode + emoji send arrives intact in the lead pane" sh -c 'echo "$1" | grep -qF "[BRIDGE from laptop] $2"' _ "$(pane)" "$U"
V "~/.local/bin/bridge reply '$U'" >/dev/null
t "unicode + emoji reply round-trips intact" sh -c 'echo "$1" | grep -qF "$2"' _ "$(L 'bridge inbox')" "$U"
# 20 KB message: the server keeps the first 8192 bytes (MAX_MSG); the lead pane keeps working
L 'printf "BEGINMARK %s ENDMARK" "$(head -c 20000 /dev/zero | tr "\0" "x")" | bridge send' >/dev/null 2>&1; sleep 2
t "a 20 KB message is cut to the 8 KB limit in the log" V 'l=$(grep -c . ~/.pierce-skill-kit/bridge/messages.tsv); m=$(grep BEGINMARK ~/.pierce-skill-kit/bridge/messages.tsv | tail -1); [ -n "$m" ] && [ ${#m} -lt 8400 ] && ! echo "$m" | grep -q ENDMARK && [ "$l" -gt 0 ]'
L 'bridge send "after the long one"' >/dev/null 2>&1; sleep 1
t "the lead pane still takes messages after a 20 KB one" sh -c 'echo "$1" | grep -qF "[BRIDGE from laptop] after the long one"' _ "$(pane)"
t "the lead window is still alive after a 20 KB one" V 'tmux has-session -t hub && tmux list-windows -t hub -F "#{window_name}" | grep -qx Lead'
L 'bridge send "concurrent-A-1111111111111111111111111111" > /tmp/c1.out 2>&1 & bridge send "concurrent-B-2222222222222222222222222222" > /tmp/c2.out 2>&1 & wait'; sleep 3
cp1=$(pane)
t "two simultaneous sends both land" sh -c 'echo "$1" | grep -qF "concurrent-A-1111111111111111111111111111" && echo "$1" | grep -qF "concurrent-B-2222222222222222222222222222"' _ "$cp1"
t "two simultaneous sends are not interleaved (each is one whole line)" sh -c 'echo "$1" | grep -qE "^.{0,3}.*\[BRIDGE from laptop\] concurrent-A-1{28} \(answer with: bridge reply \"\.\.\.\"\)" && echo "$1" | grep -qE "\[BRIDGE from laptop\] concurrent-B-2{28} \(answer with: bridge reply \"\.\.\.\"\)"' _ "$cp1"
t "both simultaneous senders were told delivered" L 'grep -q delivered /tmp/c1.out && grep -q delivered /tmp/c2.out'

echo "== errors: unauthorized key and unreachable server"
L 'rm -rf /tmp/bdbad && mkdir -p /tmp/bdbad && ssh-keygen -q -t ed25519 -N "" -f /tmp/bdbad/key </dev/null'
L 'printf "BRIDGE_VPS=tester@vps\nBRIDGE_NAME=laptop\nBRIDGE_KEY=/tmp/bdbad/key\n" > /tmp/bdbad/config; mkdir -p /tmp/bdbad2; printf "BRIDGE_VPS=tester@nohost-x\nBRIDGE_NAME=laptop\nBRIDGE_KEY=\n" > /tmp/bdbad2/config'
for c in 'send hi' 'inbox' 'sync'; do
  for d in bdbad bdbad2; do
    o=$(L "BRIDGE_DIR=/tmp/$d timeout 60 bridge $c </dev/null 2>&1"); rc=$?
    if [ $rc != 0 ] && [ $rc != 124 ] && [ -n "$o" ] && ! echo "$o" | grep -qE 'delivered|synced|no new messages'; then ok "$d: bridge $c fails with a message ($(echo "$o" | head -1 | cut -c1-70))"; else no "$d: bridge $c (rc=$rc: $o)"; fi
  done
done
o=$(L 'BRIDGE_DIR=/tmp/bdbad bridge inbox </dev/null 2>&1')
t "unauthorized key: the error says why" sh -c 'echo "$1" | grep -qiE "permission denied|publickey|could not reach"' _ "$o"
o=$(L 'BRIDGE_DIR=/tmp/bdbad2 bridge send hi </dev/null 2>&1')
t "unreachable server: the error names the problem" sh -c 'echo "$1" | grep -qiE "resolve|connect|unreachable|no route|name or service"' _ "$o"
t "failed sends never reached the lead" sh -c '! echo "$1" | grep -q "BRIDGE from laptop\] hi "' _ "$(pane)"
o=$(L 'BRIDGE_DIR=/tmp/nosuchdir bridge send hi 2>&1'); rc=$?
t "a missing config says to run setup" sh -c '[ "$1" != 0 ] && echo "$2" | grep -q "not set up yet"' _ "$rc" "$o"

echo "== sync"
L "mkdir -p $LC/briefs && echo local-brief > $LC/briefs/a.md"
V "mkdir -p $SH && echo '- decided X' > $SH/decisions.md"
L 'bridge sync' >/dev/null 2>&1
t "sync up: local brief is on the vps" V "grep -qx local-brief $SH/briefs/a.md"
t "sync down: vps decisions are local" L "grep -qx -- '- decided X' $LC/decisions.md"
L "echo local-v2 > $LC/briefs/a.md"; V "echo server-v2 > $SH/briefs/a.md"
sout=$(L 'bridge sync' 2>&1)
t "conflict is reported" sh -c 'echo "$1" | grep -q "conflict: briefs/a.md"' _ "$sout"
t "conflict keeps both locally" L "grep -qx server-v2 $LC/briefs/a.md && cat $LC/briefs/a.md.conflict-laptop-* | grep -qx local-v2"
t "conflict keeps both on the vps" V "grep -qx server-v2 $SH/briefs/a.md && cat $SH/briefs/a.md.conflict-laptop-* | grep -qx local-v2"
L "rm $LC/decisions.md && bridge sync" >/dev/null 2>&1
t "a local delete propagates" V "test ! -e $SH/decisions.md"
V "rm $SH/briefs/a.md.conflict-laptop-*"; L 'bridge sync' >/dev/null 2>&1
t "a server delete propagates" L "! ls $LC/briefs/ | grep -q conflict"

echo "== deny-list (both directions)"
DENY='.env .env.local x.pem x.key id_ed25519 id_rsa.pub my-secret.txt SECRETS.md x.p12 x.pfx .ssh/config .secrets/a.txt credentials.json api_token.txt .git/config deep/dir/.env .netrc .npmrc .pypirc .pgpass .git-credentials .aws/config .docker/config.json kubeconfig vault.kdbx putty.ppk notes.gpg key.asc .htpasswd my-credential.txt'
mk="for f in $DENY ok.md; do mkdir -p \$(dirname \$B/\$f) && echo sensitive > \$B/\$f; done"
L "B=$LC/l; $mk"; V "B=$SH/v; $mk"
files=$(L 'bridge files')
leak=0; for f in $DENY; do echo "$files" | grep -qxF "l/$f" && { echo "  client would send l/$f"; leak=1; }; done
[ $leak = 0 ] && echo "$files" | grep -qx l/ok.md && ok "client-side filter: no deny-listed file is queued" || no "client-side filter"
L 'bridge sync' >/dev/null 2>&1
t "allowed files crossed both ways" VL "test -f $SH/l/ok.md" "test -f $LC/v/ok.md"
leak=0
for f in $DENY; do
  V "test -e $SH/l/$f" && { echo "  leaked up: $f"; leak=1; }
  L "test -e $LC/v/$f" && { echo "  leaked down: $f"; leak=1; }
done
[ $leak = 0 ] && ok "no deny-listed file crossed in either direction ($(echo $DENY | wc -w) patterns)" || no "deny-list leak"
t "deny-listed files stay untouched where they live" VL "test -f $SH/v/.env" "test -f $LC/l/.ssh/config"
# server side on its own: a hand-made archive that skips the client filter
L 'cd /tmp && rm -rf cr && mkdir -p cr/x && cd cr && echo s > .env && echo s > x/id_rsa && echo s > server.pem && echo fine > crafted-ok.md && tar -cf ../crafted.tar . && ssh -o BatchMode=yes tester@vps "~/.local/bin/bridge-serve sync crafted" < ../crafted.tar > /dev/null'
t "server-side filter: crafted archive's allowed file stored" V "test -f $SH/crafted-ok.md"
t "server-side filter: crafted archive's secrets not stored" V "test ! -e $SH/.env && test ! -e $SH/x/id_rsa && test ! -e $SH/server.pem"
L 'cd /tmp && rm -rf ln && mkdir ln && ln -s /home/tester/.ssh ln/s && tar -cf ln.tar -C ln . && ! ssh -o BatchMode=yes tester@vps "~/.local/bin/bridge-serve sync crafted" < ln.tar 2>/tmp/ln.err >/dev/null'
t "server refuses an archive holding a symlink" L 'grep -q "links or special files" /tmp/ln.err'
L 'cd /tmp && echo x > dd && tar -cPf dd.tar --transform "s|^dd|../dd|" dd && ! ssh -o BatchMode=yes tester@vps "~/.local/bin/bridge-serve sync crafted" < dd.tar 2>/tmp/dd.err >/dev/null'
t "server refuses an archive with ../ paths" VL "test ! -e /home/tester/.pierce-skill-kit/dd" "grep -q 'unsafe paths' /tmp/dd.err"

echo "== archive bombs and caps (sent straight to bridge-serve)"
SS='ssh -o BatchMode=yes tester@vps "~/.local/bin/bridge-serve sync crafted"'
L 'cd /tmp && rm -rf bomb && mkdir bomb && head -c 3000000 /dev/zero > bomb/zero.bin && tar -cf bomb.tar -C bomb . && gzip -kf bomb.tar && xz -kf bomb.tar && bzip2 -kf bomb.tar'
for z in gz xz bz2; do
  o=$(L "$SS < /tmp/bomb.tar.$z 2>&1 >/dev/null"); rc=$?
  if [ $rc != 0 ] && echo "$o" | grep -q "not a plain tar"; then ok "server refuses a .$z archive before extracting"; else no "$z archive (rc=$rc: $o)"; fi
done
o=$(L "$SS < /tmp/bomb.tar 2>&1 >/dev/null"); rc=$?
[ $rc != 0 ] && echo "$o" | grep -q "over the 1 MB cap" && ok "server refuses an archive listing a file over 1 MB" || no "oversize listing (rc=$rc: $o)"
L 'cd /tmp && rm -rf sp && mkdir sp && truncate -s 60M sp/sparse && tar -cSf sp.tar -C sp .'
o=$(L "$SS < /tmp/sp.tar 2>&1 >/dev/null"); rc=$?
[ $rc != 0 ] && echo "$o" | grep -q "refusing archive" && ok "server refuses a sparse 60 MB file in a tiny archive" || no "sparse (rc=$rc: $o)"
L 'cd /tmp && rm -rf many && mkdir many && cd many && seq 1 5001 | xargs touch && tar -cf ../many.tar .'
o=$(L "$SS < /tmp/many.tar 2>&1 >/dev/null"); rc=$?
[ $rc != 0 ] && echo "$o" | grep -q "over 5000 entries" && ok "server refuses an archive with over 5000 entries" || no "entry cap (rc=$rc: $o)"
t "none of the refused archives left files on the vps" V "test ! -e $SH/zero.bin && test ! -e $SH/sparse && test ! -e $SH/1"

echo "== links inside the shared folders"
V "mkdir -p ~/outside && ln -s ~/outside $SH/linked"
L "mkdir -p $LC/linked && echo via-link > $LC/linked/x.md"
o=$(L 'bridge sync' 2>&1)
t "server never writes through a linked subfolder" V "test ! -e ~/outside/x.md"
t "server keeps that content under a flat name" V "grep -qx via-link $SH/blocked-laptop-linked_x.md"
echo "$o" | grep -q "link on the server" && ok "the sender is told" || no "link note ($o)"
V "rm $SH/linked $SH/blocked-laptop-linked_x.md"; L "rm -rf $LC/linked $LC/blocked-laptop-linked_x.md"; L 'bridge sync' >/dev/null 2>&1
L "mkdir -p /tmp/out && ln -s /tmp/out $LC/lnk"; V "mkdir -p $SH/lnk && echo from-server > $SH/lnk/y.md"
L 'bridge sync' >/dev/null 2>&1
t "client never writes through a linked subfolder" L "test ! -e /tmp/out/y.md && grep -qx from-server $LC/blocked-lnk_y.md"
L "rm $LC/lnk $LC/blocked-lnk_y.md"; V "rm -rf $SH/lnk $SH/blocked-lnk_y.md"; L 'bridge sync' >/dev/null 2>&1

echo "== size caps"
sout=$(L "head -c 2000000 /dev/zero > $LC/big.bin && bridge sync" 2>&1)
t "a 2 MB file is skipped with a note" sh -c 'echo "$1" | grep -q "big.bin.*over the 1 MB cap"' _ "$sout"
t "the 2 MB file did not reach the vps" V "test ! -e $SH/big.bin"
L "mkdir -p $LC/bulk && for i in \$(seq 1 55); do head -c 1000000 /dev/zero > $LC/bulk/f\$i; done"
sout=$(L 'bridge sync' 2>&1); rc=$?
[ $rc != 0 ] && echo "$sout" | grep -q "50 MB total cap" && ok "a 55 MB folder is refused (total cap)" || no "total cap (rc=$rc: $sout)"
t "nothing from the refused sync reached the vps" V "test ! -e $SH/bulk"
L "rm -rf $LC/bulk $LC/big.bin"

echo "== a plain shell in the lead window is never typed into"
V "tmux new-window -d -t hub -n ShellTest sh && echo LK_LEAD_WINDOW=ShellTest >> ~/.config/pierce-skill-kit/config"
o=$(L 'bridge send "rm -rf ~ please"' 2>&1); rc=$?
[ $rc = 4 ] && echo "$o" | grep -q "plain sh shell" && ok "send to a shell pane is refused and the sender told" || no "shell pane (rc=$rc: $o)"
sleep 1
t "nothing was typed into the shell pane" sh -c '! echo "$1" | grep -q "please"' _ "$(V 'tmux capture-pane -p -t hub:ShellTest')"
t "the held message is kept on the vps" V 'grep -q "rm -rf ~ please" ~/.pierce-skill-kit/bridge/messages.tsv'
V "sed -i /LK_LEAD_WINDOW=ShellTest/d ~/.config/pierce-skill-kit/config && tmux kill-window -t hub:ShellTest"

echo "== escapes in replies are stripped"
V "~/.local/bin/bridge reply \"\$(printf 'esc\\033]0;pwned\\007-test\\033[31m')\""
t "inbox prints no escape characters" sh -c '[ -z "$(printf %s "$1" | tr -d "\n" | LC_ALL=C tr -d " -~")" ] && echo "$1" | grep -q "esc"' _ "$(L 'bridge inbox')"

echo "== file modes (umask 077)"
t "vps log, messages, outbox are 600 and shared/ is 700" V "[ \"\$(stat -c %a ~/.pierce-skill-kit/bridge.log ~/.pierce-skill-kit/bridge/messages.tsv ~/.pierce-skill-kit/bridge/outbox.tsv $SH | tr '\n' ' ')\" = '600 600 600 700 ' ]"
t "local inbox and config are 600" L '[ "$(stat -c %a ~/pierce-bridge/inbox.txt ~/pierce-bridge/config | tr "\n" " ")" = "600 600 " ]'

echo "== MCP server (scripted JSON-RPC)"
L "printf '%s\n' \
 '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"e2e\",\"version\":\"1\"}}}' \
 '{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}' \
 '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}' \
 '{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"send_to_lead\",\"arguments\":{\"text\":\"mcp says hi\"}}}' \
 '{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"share_context\",\"arguments\":{\"path\":\"notes/mcp.md\",\"content\":\"from mcp\"}}}' \
 '{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"no_such_tool\",\"arguments\":{}}}' \
 '{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"server/discover\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientInfo\":{\"name\":\"e2e\",\"version\":\"1\"},\"io.modelcontextprotocol/clientCapabilities\":{}}}}' \
 '{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"1900-01-01\"}}}' \
 | node ~/pierce-bridge/bin/mcp.mjs > /tmp/mcp.out"
mcp=$(L 'node -e '\''
const r = Object.fromEntries(require("fs").readFileSync("/tmp/mcp.out","utf8").trim().split("\n").map(l => JSON.parse(l)).map(m => [m.id, m]));
const ok = (c, m) => console.log((c ? "ok " : "bad ") + m);
ok(r[1].result.protocolVersion === "2025-06-18" && r[1].result.capabilities.tools && r[1].result.serverInfo.name, "initialize");
ok(JSON.stringify(r[2].result.tools.map(t => t.name)) === JSON.stringify(["send_to_lead","read_inbox","share_context","pull_context"]) && r[2].result.tools.every(t => t.inputSchema.type === "object"), "tools/list");
ok(r[3].result.isError === false && /delivered/.test(r[3].result.content[0].text), "tools/call send_to_lead");
ok(r[4].result.isError === false, "tools/call share_context");
ok(r[5].error && r[5].error.code === -32602, "unknown tool error");
ok(r[6].result.resultType === "complete" && r[6].result.supportedVersions.includes("2026-07-28"), "server/discover");
ok(r[7].error && r[7].error.code === -32022, "unsupported version error");
ok(Object.keys(r).length === 7, "one answer per request, none for the notification");
'\'' 2>&1')
echo "$mcp" | while IFS= read -r l; do case $l in ok*) echo "PASS: MCP ${l#ok }";; *) echo "FAIL: MCP ${l#bad }";; esac; done
echo "$mcp" | grep -qv '^ok ' && fails=$((fails + 1))
echo "== MCP server: bad input"
L "printf '%s\n' \
 'this is not json' \
 '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"definitely_not_a_tool\",\"arguments\":{}}}' \
 '[1,2,3]' \
 '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"send_to_lead\"}}' \
 '{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"no/such/method\"}' \
 '{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":null}' \
 '{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"ping\"}' \
 | node ~/pierce-bridge/bin/mcp.mjs > /tmp/mcp2.out 2>/tmp/mcp2.err; echo exit=\$? > /tmp/mcp2.rc"
mcp2=$(L 'node -e '\''
const ls = require("fs").readFileSync("/tmp/mcp2.out","utf8").trim().split("\n").map(l => JSON.parse(l));
const ok = (c, m) => console.log((c ? "ok " : "bad ") + m);
const by = id => ls.find(m => m.id === id);
ok(ls[0].id === null && ls[0].error.code === -32700, "malformed JSON line answered with a parse error");
ok(by(1).error.code === -32602 && /definitely_not_a_tool/.test(by(1).error.message), "unknown tool name returns a JSON-RPC error");
ok(ls.some(m => m.id === null && m.error.code === -32600), "a JSON array is an invalid request, not a crash");
ok(by(2).result.isError === true, "send_to_lead without arguments is a tool error");
ok(by(3).error.code === -32601, "unknown method returns method-not-found");
ok(by(4).error || by(4).result, "null params still get an answer");
ok(by(5).result && !by(5).error, "the server kept serving after all the bad lines");
'\'' 2>&1; cat /tmp/mcp2.rc; cat /tmp/mcp2.err')
echo "$mcp2" | grep -E '^(ok|bad) ' | while IFS= read -r l; do case $l in ok*) echo "PASS: MCP ${l#ok }";; *) echo "FAIL: MCP ${l#bad }";; esac; done
echo "$mcp2" | grep -E '^(bad|Error|.*SyntaxError)' >/dev/null && { fails=$((fails + 1)); echo "$mcp2" | head -5; }
t "the MCP server exited cleanly (no crash, no stderr noise)" sh -c 'echo "$1" | grep -qx "exit=0" && [ "$(echo "$1" | grep -c "^ok ")" = 7 ]' _ "$mcp2"
sleep 1
t "MCP send_to_lead landed in the lead pane" sh -c 'echo "$1" | grep -qF "[BRIDGE from laptop] mcp says hi"' _ "$(pane)"
t "MCP share_context reached the vps" V "grep -qx 'from mcp' $SH/notes/mcp.md"

echo "== forced command (--harden)"
hout=$(L 'echo y | /kit/mods/bridge/bridge setup tester@vps --name laptop --harden' 2>&1)
t "harden shows the exact authorized_keys line first" sh -c 'echo "$1" | grep -q "command=\"~/.local/bin/bridge-serve\",restrict ssh-ed25519 "' _ "$hout"
t "harden installed exactly one forced-command line" V '[ "$(grep -c "^command=\"~/.local/bin/bridge-serve\",restrict " ~/.ssh/authorized_keys)" = 1 ]'
t "config now uses the bridge key" L 'grep -qx BRIDGE_KEY=/root/pierce-bridge/bridge_key ~/pierce-bridge/config'
L 'bridge send "via the forced key"' >/dev/null 2>&1; sleep 1
t "send works through the forced command" sh -c 'echo "$1" | grep -qF "[BRIDGE from laptop] via the forced key"' _ "$(pane)"
V '~/.local/bin/bridge reply "forced reply"' >/dev/null
t "inbox works through the forced command" sh -c 'echo "$1" | grep -q "forced reply"' _ "$(L 'bridge inbox')"
t "sync works through the forced command" L 'bridge sync'
K='ssh -T -o BatchMode=yes -i /root/pierce-bridge/bridge_key -o IdentitiesOnly=yes tester@vps'
for c in bash 'bash -c id' 'cat /etc/passwd' 'id' '~/.local/bin/bridge-serve send laptop; id' '~/.local/bin/bridge-serve add-key' '~/.local/bin/bridge-serve fetch 0 && id' 'sh -i'; do
  o=$(L "$K '$c' </dev/null 2>&1"); rc=$?
  if [ $rc = 3 ] && ! echo "$o" | grep -qE 'uid=|root:'; then ok "forced command refuses: $c"; else no "forced command refuses: $c (rc=$rc: $o)"; fi
done
o=$(L "$K </dev/null 2>&1"); rc=$?
[ $rc = 3 ] && ok "forced command refuses a plain login (no shell)" || no "plain login (rc=$rc: $o)"
t "refusals are logged on the vps" V 'grep -q "REFUSED not a bridge action: bash" ~/.pierce-skill-kit/bridge.log'
t "every action is logged on the vps" V 'grep -q "	send laptop" ~/.pierce-skill-kit/bridge.log && grep -q "	sync laptop" ~/.pierce-skill-kit/bridge.log && grep -q "	fetch " ~/.pierce-skill-kit/bridge.log'

echo "== bridge.ps1 (PowerShell 7 on Linux)"
t "bridge.ps1 parses" W 'pwsh -NoProfile -c "\$e=\$null;\$t=\$null;[void][System.Management.Automation.Language.Parser]::ParseFile(\"/kit/mods/bridge/bridge.ps1\",[ref]\$t,[ref]\$e); if(\$e){\$e; exit 1}"'
P='pwsh -NoProfile -File /root/pierce-bridge/bin/bridge.ps1'
wout=$(W 'pwsh -NoProfile -File /kit/mods/bridge/bridge.ps1 setup tester@vps -Name winbox' 2>&1)
t "ps1 setup works" sh -c 'echo "$1" | grep -q "lead window hub:Lead running" && echo "$1" | grep -qF "claude mcp add -s user bridge -- node"' _ "$wout"
W "$P send 'hello from powershell'" >/dev/null 2>&1; sleep 1
t "ps1 send lands in the lead pane" sh -c 'echo "$1" | grep -qF "[BRIDGE from winbox] hello from powershell"' _ "$(pane)"
V '~/.local/bin/bridge reply "hi winbox"' >/dev/null
t "ps1 inbox gets the reply" sh -c 'echo "$1" | grep -q "hi winbox"' _ "$(W "$P inbox")"
t "ps1 inbox marks read" sh -c 'echo "$1" | grep -q "no new messages"' _ "$(W "$P inbox")"
W 'C=/root/pierce-bridge/context; mkdir -p $C/w $C/w/.ssh && echo from-win > $C/w/note.md && echo s > $C/w/.env && echo s > $C/w/key.pem && echo s > $C/w/.ssh/config'
W "$P sync" >/dev/null 2>&1
t "ps1 sync up" V "grep -qx from-win $SH/w/note.md"
t "ps1 sync down (files from the other client)" W 'test -f /root/pierce-bridge/context/notes/mcp.md'
t "ps1 sync never sends deny-listed files" V "test ! -e $SH/w/.env && test ! -e $SH/w/key.pem && test ! -e $SH/w/.ssh/config"
V "echo win-server > $SH/w/note.md"; W 'echo win-local > /root/pierce-bridge/context/w/note.md'
W "$P sync" >/dev/null 2>&1
t "ps1 conflict keeps both" W 'grep -qx win-server /root/pierce-bridge/context/w/note.md && cat /root/pierce-bridge/context/w/note.md.conflict-winbox-* | grep -qx win-local'
hw=$(W 'echo y | pwsh -NoProfile -File /kit/mods/bridge/bridge.ps1 setup tester@vps -Name winbox -Harden' 2>&1)
t "ps1 -Harden adds the forced-command key" sh -c 'echo "$1" | grep -q "restrict ssh-ed25519" && echo "$1" | grep -q "done\."' _ "$hw"
W "$P send 'ps1 via forced key'" >/dev/null 2>&1; sleep 1
t "ps1 send through the forced command" sh -c 'echo "$1" | grep -qF "[BRIDGE from winbox] ps1 via forced key"' _ "$(pane)"

echo "== bridge.ps1: hostile archives from the server (a fake ssh hands it crafted tars)"
L 'rm -rf /tmp/h && mkdir -p /tmp/h/ok /tmp/h/big /tmp/h/ln && cd /tmp/h && echo fine > ok/f.md && tar -cf plain.tar -C ok . && gzip -kf plain.tar && xz -kf plain.tar && bzip2 -kf plain.tar
  head -c 2000000 /dev/zero > big/huge.bin && tar -cf big.tar -C big .
  echo x > dd && tar -cPf dots.tar --transform "s|^dd|../dd|" dd
  echo x > abs && tar -cPf abs.tar --transform "s|^abs|/tmp/abs-evil|" abs
  echo x > bs && tar -cf bsl.tar --transform "s|^bs|dir\\\\evil|" bs
  echo x > dr && tar -cf drv.tar --transform "s|^dr|C:evil|" dr
  ln -s /etc/passwd ln/s && tar -cf link.tar -C ln .'
for f in plain.tar plain.tar.gz plain.tar.xz plain.tar.bz2 big.tar dots.tar abs.tar bsl.tar drv.tar link.tar; do
  $D exec "$N-local" cat "/tmp/h/$f" | $D exec -i "$N-win" sh -c "mkdir -p /tmp/h && cat > /tmp/h/$f"
done
W 'mkdir -p /tmp/fakebin /tmp/bdw/context && printf "#!/bin/sh\ncat >/dev/null\ncat \"\$FAKE_TAR\"\n" > /tmp/fakebin/ssh && chmod +x /tmp/fakebin/ssh && printf "BRIDGE_VPS=fake@host\nBRIDGE_NAME=winbox\nBRIDGE_KEY=\n" > /tmp/bdw/config && echo mine > /tmp/bdw/context/mine.md'
hostile() { # hostile <tar> <expected message>
  o=$(W "FAKE_TAR=/tmp/h/$1 PATH=/tmp/fakebin:\$PATH BRIDGE_DIR=/tmp/bdw pwsh -NoProfile -File /kit/mods/bridge/bridge.ps1 sync 2>&1"); rc=$?
  if [ $rc != 0 ] && echo "$o" | grep -q "$2"; then ok "ps1 refuses $1: $2"; else no "ps1 refuses $1 (rc=$rc: $o)"; fi
}
hostile plain.tar.gz "not a plain tar"
hostile plain.tar.xz "not a plain tar"
hostile plain.tar.bz2 "not a plain tar"
hostile big.tar "1 MB cap"
hostile dots.tar "unsafe paths"
hostile abs.tar "unsafe paths"
hostile bsl.tar "unsafe paths"
hostile drv.tar "unsafe paths"
hostile link.tar "links or special files"
t "ps1: none of the hostile archives wrote anything" W 'test ! -e /tmp/abs-evil && test ! -e /tmp/dd && ! ls /tmp/bdw/context | grep -qE "evil|huge|passwd|^s$" && grep -qx mine /tmp/bdw/context/mine.md'
o=$(W 'FAKE_TAR=/tmp/h/plain.tar PATH=/tmp/fakebin:$PATH BRIDGE_DIR=/tmp/bdw pwsh -NoProfile -File /kit/mods/bridge/bridge.ps1 sync 2>&1')
t "ps1: a clean plain tar from the same fake still syncs (control)" sh -c 'echo "$1" | grep -q "synced 1 files" ' _ "$o"
o=$(W 'FAKE_TAR=/dev/null PATH=/tmp/fakebin:$PATH BRIDGE_DIR=/tmp/bdw pwsh -NoProfile -File /kit/mods/bridge/bridge.ps1 inbox 2>&1'); rc=$?
t "ps1: an empty server answer to inbox is handled" sh -c '[ "$1" = 0 ] && echo "$2" | grep -q "no new messages"' _ "$rc" "$o"

echo "== bridge.ps1: messaging edge cases and errors"
UP='ps1 héllo 日本語 🚀 ñ'
W "$P send '$UP'" >/dev/null 2>&1; sleep 1
t "ps1 unicode + emoji send arrives intact" V "grep -qF '$UP' ~/.pierce-skill-kit/bridge/messages.tsv"
V "~/.local/bin/bridge reply '$UP'" >/dev/null
t "ps1 unicode + emoji reply round-trips intact" sh -c 'echo "$1" | grep -qF "$2"' _ "$(W "$P inbox")" "$UP"
t "ps1 inbox --all shows history" sh -c 'echo "$1" | grep -q "hi winbox"' _ "$(W "$P inbox --all")"
t "ps1 inbox again: nothing new" sh -c 'echo "$1" | grep -q "no new messages"' _ "$(W "$P inbox")"
W "printf 'BEGINMARK %s ENDMARK' \"\$(head -c 20000 /dev/zero | tr '\\0' x)\" | $P send" >/dev/null 2>&1; sleep 2
t "ps1 20 KB message is cut to the 8 KB limit" V 'm=$(grep BEGINMARK ~/.pierce-skill-kit/bridge/messages.tsv | tail -1); [ -n "$m" ] && [ ${#m} -lt 8400 ] && ! echo "$m" | grep -q ENDMARK'
W "$P send 'ps1 after the long one'" >/dev/null 2>&1; sleep 1
t "ps1: the lead pane still takes messages after a 20 KB one" sh -c 'echo "$1" | grep -qF "[BRIDGE from winbox] ps1 after the long one"' _ "$(pane)"
W 'mkdir -p /tmp/bdw3 && ssh-keygen -q -t ed25519 -N "" -f /tmp/bdw3/key </dev/null; printf "BRIDGE_VPS=tester@vps\nBRIDGE_NAME=winbox\nBRIDGE_KEY=/tmp/bdw3/key\n" > /tmp/bdw3/config; mkdir -p /tmp/bdw4; printf "BRIDGE_VPS=tester@nohost-x\nBRIDGE_NAME=winbox\nBRIDGE_KEY=\n" > /tmp/bdw4/config'
for c in 'send hi' 'inbox' 'sync'; do
  for d in bdw3 bdw4; do
    o=$(W "BRIDGE_DIR=/tmp/$d timeout 90 pwsh -NoProfile -File /kit/mods/bridge/bridge.ps1 $c </dev/null 2>&1"); rc=$?
    if [ $rc != 0 ] && [ $rc != 124 ] && [ -n "$o" ] && ! echo "$o" | grep -qE 'delivered|^synced|no new messages'; then ok "ps1 $d: $c fails with a message ($(echo "$o" | head -1 | cut -c1-70))"; else no "ps1 $d: $c (rc=$rc: $o)"; fi
  done
done

echo
if [ $fails = 0 ]; then echo "ALL BRIDGE E2E TESTS PASSED"; else echo "$fails FAILED"; exit 1; fi
