#!/bin/sh
# brain-loop (vault, report router, plan-grade, MCP server, /brain page, hook, stuck-check, installer) on fake data,
# in a throwaway container. No network: Jev is a fake local server and the Claude check is a stub script.
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/brain-loop-test.sh
set -e
[ -f /.dockerenv ] || [ -n "$LK_IN_CONTAINER" ] || { echo "brain-loop-test: run it in a container (see the first lines)"; exit 2; }
apt-get update -qq >/dev/null && apt-get install -y -qq python3 jq >/dev/null 2>&1
cp -r /kit /tmp/kit; cd /tmp/kit
export HOME=/tmp/h; mkdir -p "$HOME"
n=0; ok() { n=$((n + 1)); echo "ok: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
bl() { sh /tmp/kit/mods/brain-loop/bin/brain-loop "$@"; }

# --- the committed example vault is exactly what the builder makes from the fake inputs
sh examples/brain-loop-inputs/make-vault.sh /tmp/ex >/dev/null
diff -r examples/brain-vault /tmp/ex >/dev/null || { diff -r examples/brain-vault /tmp/ex | head -20; fail "example vault differs from a fresh build"; }
ok "examples/brain-vault == a fresh build from examples/brain-loop-inputs"

# --- a working copy of the fake inputs, with its own config
W=/tmp/w; mkdir -p $W/lead $W/acme-site; cp -r examples/brain-loop-inputs $W/in
printf '#!/bin/sh\nprintf "%%s\\n" "$1" >> %s/said.txt\n' "$W" > $W/say.sh
cat > $W/config <<EOF
LK_HOME=$W/home
LK_LEAD_DIR=$W/lead
LK_CHECK_KEY_FILE=$W/no-key.env
BRAIN_VAULT=$W/vault
BRAIN_ENTITIES=$W/in/entities.json
BRAIN_REPORTS=$W/in/reports.tsv
BRAIN_ORDERS=$W/in/orders.tsv
BRAIN_DECISIONS=$W/in/decisions.md
BRAIN_PLANS=$W/in/plans
BRAIN_MEMORY_DIRS=$W/in/memory
BRAIN_LEDGER=$W/in/ledger.tsv
BRAIN_SAY="sh $W/say.sh"
BRAIN_NOW=2026-10-15T12:00
EOF
export LK_CONFIG=$W/config
said() { grep -c "$1" $W/said.txt 2>/dev/null || true; }

bl build | grep -q '"open_items": 9' || fail "build: expected 9 open items"
ok "build: 25 notes, 9 open items from the fake ledgers"

# --- hand edits survive a rebuild; the generated block is rewritten, not duplicated
echo "my own line: Dana prefers calls after 3pm" >> $W/vault/projects/acme-site.md
bl build >/dev/null
grep -q "my own line: Dana prefers calls" $W/vault/projects/acme-site.md || fail "hand text lost on rebuild"
[ "$(grep -c 'brain:generated (rebuilt' $W/vault/projects/acme-site.md)" = 1 ] || fail "generated block duplicated"
ok "text below the end marker survives a rebuild"

# --- my_* overrides win: close, reassign, snooze, rename
bl mark c-order-4 --status "done" --note "menu live, screenshot menu.png" >/dev/null
bl open 30 | grep -q c-order-4 && fail "closed item still open before rebuild"
bl mark c-order-3 --owner sam-sample >/dev/null
bl mark c-in-l1 --chase 2026-10-01 >/dev/null
bl mark c-order-2 --title "Staging link to Dana (renamed)" >/dev/null
bl mark c-nope --status "done" >/dev/null && fail "mark on a missing note succeeded"
bl build | grep -q '"open_items": 8' || fail "closed item came back after rebuild"
grep -q '^my_status: "done"' $W/vault/commitments/c-order-4.md || fail "my_status lost"
bl open 30 | grep -q "owner sam-sample.*c-order-3" || fail "my_owner did not win"
grep -q "^# Staging link to Dana (renamed)" $W/vault/commitments/c-order-2.md || fail "my_title did not win"
ok "my_status / my_owner / my_title / my_chase_after survive rebuilds and win"

# --- brain_open is in chase order, and the snoozed-earlier item is first
bl open 30 | sed -n 's/.*chase \([0-9-]*\)\].*/\1/p' > $W/chase.txt
[ "$(wc -l < $W/chase.txt)" = 8 ] || fail "open list length"
sort -c $W/chase.txt || fail "open list not sorted by chase_after"
bl open 30 | sed -n 2p | grep -q c-in-l1 || fail "my_chase_after did not move the item up"
ok "brain_open sorted by chase_after"

# --- fuzzy lookup, and source cleanup that spares hand-written notes
bl show "what does dana still owe us" | grep -q '"id": "dana-example"' || fail "show: question naming a person"
d1=$(basename $W/vault/decisions/*menu-prices*); d2=$(basename $W/vault/decisions/*checkout-ships*)
echo "keep: asked Lee twice" >> $W/vault/decisions/$d1
sed -i '1,2d' $W/in/decisions.md; bl build >/dev/null
[ -f $W/vault/decisions/$d1 ] || fail "hand-written note deleted with its source"
[ -f $W/vault/decisions/$d2 ] && fail "orphan note kept"
ok "show resolves a question; orphan notes go unless you wrote in them"

# --- plan-new from the tab-plan template
p=$(bl plan-new beta-app "store listing")
[ "$p" = "$W/in/plans/beta-app/1015-store-listing.md" ] && grep -q "Owner tab: beta-app" "$p" || fail "plan-new: $p"
ok "plan-new fills the template"

# --- router: first run starts at the end, then triage + apply once + batched lead message
bl route run --apply | grep -q '"new": 0' || fail "first run replayed history"
T=$(printf '\t')
cat >> $W/in/reports.tsv <<EOF
2026-10-15T09:00Z${T}acme-site${T}done${T}test order placed (row 1), screenshot attached. NEXT: confirmation email${T}/tmp/kit/README.md${T}acme-site
2026-10-15T09:30Z${T}harbor-cafe${T}progress${T}photos added to the menu page${T}${T}harbor-cafe
2026-10-15T10:00Z${T}beta-app${T}needs-human${T}Sam sent the screenshots (order #3); OK to publish the listing? NEXT: publish after your OK${T}${T}beta-app
EOF
out=$(bl route run --apply); echo "    $out"
printf '%s\n' "$out" | grep -q '"new": 3' || fail "router did not see 3 new reports"
A=$W/in/plans/acme-site/1013-checkout.md; H=$W/in/plans/harbor-cafe/1012-menu.md
grep -q "^- 2026-10-15T09:00 \[done\] acme-site: test order placed" $A || fail "no progress line in the acme plan"
grep -q "^- 2026-10-15T09:30 \[progress\] harbor-cafe: photos" $H || fail "no progress line in the harbor plan"
grep -q '^my_status: "done"' $W/vault/commitments/c-order-1.md || fail "proven done report did not mark order 1"
grep -q "2026-10-15T10:00 needs-human: Sam sent the screenshots" $W/in/orders.tsv || fail "order #3 not touched"
[ "$(said '\[brain-loop\]')" = 1 ] && grep -q "harbor-cafe: report has no NEXT" $W/said.txt || fail "lead not told once about the missing NEXT"
ok "router: progress lines, brain_mark on a proven row, order note, one batched lead message"
bl route run --apply --since 2 >/dev/null; s1=$(md5sum $A $H $W/in/orders.tsv $W/vault/commitments/c-order-1.md)
out=$(bl route run --apply --since 2); s2=$(md5sum $A $H $W/in/orders.tsv $W/vault/commitments/c-order-1.md)
[ "$s1" = "$s2" ] && printf '%s\n' "$out" | grep -q '"wrote": 0' || fail "replaying the same reports wrote again"
[ "$(grep -c '\[done\] acme-site: test order placed' $A)" = 1 ] || fail "duplicate progress line"
grep -q '^my_status: "done"' $W/vault/commitments/c-order-1.md || fail "an older replayed report overwrote a newer mark"
ok "router writes each action once (replay writes nothing)"
touch $W/home/brain-loop/OFF; st=$(cat $W/home/brain-loop/state.json)
echo "2026-10-15T11:00Z${T}acme-site${T}progress${T}email template drafted. NEXT: test send${T}${T}acme-site" >> $W/in/reports.tsv
bl route run --apply | grep -q '"off"' || fail "OFF switch ignored"
[ "$st" = "$(cat $W/home/brain-loop/state.json)" ] && ! grep -q "email template drafted" $A || fail "router wrote while OFF"
rm $W/home/brain-loop/OFF
ok "OFF switch pauses the router"
bl route dryrun --last 20 | grep -q '"reports": 11' || fail "dryrun"
bl route dryrun --engine jev --last 1 2>&1 | grep -q "spend gate closed" || fail "jev ran with no cap"
bl route run --engine hybrid 2>&1 | grep -q 'using stub' || fail "hybrid with a closed gate did not fall back to the rules"
printf '{"line": 9, "needs_owner": false, "blocked": false, "done_proven": true, "has_next": true, "urgency": 0, "plan": "%s", "rows": [1]}\n' "$A" > $W/gold.jsonl
bl route score $W/gold.jsonl $W/home/brain-loop/dryrun-stub.jsonl | grep -q "^needs_owner .* 1/1 " || fail "score"
bl route preview 9 | jq -e '.questions.needs_owner and .state.status == "done"' >/dev/null || fail "preview"
ok "dryrun, closed spend gate (no call, falls back to rules), score vs gold, preview"

# --- plan-grade: directions parsing (no model calls)
out=$(bl grade $A --dry)
printf '%s\n' "$out" | grep -q "3 directions (Directions)" && printf '%s\n' "$out" | grep -q "D3 \[Directions\] Ask before sending anything to Dana" || fail "Directions not parsed: $out"
out=$(bl grade $H --dry)
printf '%s\n' "$out" | grep -q "3 directions (Done when)" && printf '%s\n' "$out" | grep -q "D3 \[Rules\] No invoice or payment link" || fail "fallback not parsed: $out"
bl grade $A 2>&1 | grep -q "spend gate closed" || fail "grade ran with no cap"
ok "plan-grade parses Directions, falls back to Done-when + Rules, refuses with no cap"

# --- fake Jev + stub Claude check: hybrid router and a full grade, all local
cat > $W/jev.py <<'EOF'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        q = json.loads(self.rfile.read(int(self.headers["Content-Length"])))["questions"]
        if "verdict" in q:
            a = {"verdict": {"choice": "followed", "confidence": 0.4}}
        else:
            a = {"needs_owner": {"noul": 0.97}, "blocked": {"noul": 0.02}, "done_proven": {"noul": 0.5},
                 "urgency": {"score": 1, "confidence": 0.95}, "plan": {"choice": "none", "confidence": 0.3}}
        b = json.dumps({"answers": a, "usage": {"cost": 0.00004}}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
python3 $W/jev.py 8797 & JEV=$!
printf '#!/bin/sh\necho %s\n' "'{\"verdict\": \"partly\", \"why\": \"stub check\"}'" > $W/claude.sh
printf 'OPENROUTER_API_KEY=x\n' > $W/no-key.env
printf 'BRAIN_JEV_CAP_USD=1\nBRAIN_JEV_URL=http://127.0.0.1:8797/\nLK_CLAUDE="sh %s/claude.sh"\n' "$W" >> $W/config
sleep 1
bl route dryrun --engine hybrid --last 3 | grep -q '"reports": 3' || fail "hybrid dryrun"
jq -s -e 'length == 3 and .[1].needs_owner == true and .[1].conf.needs_owner >= 0.9 and .[0].conf.needs_owner == 0.6 and .[0].conf.urgency >= 0.9' \
  $W/home/brain-loop/dryrun-hybrid.jsonl >/dev/null || fail "hybrid: agreeing confident answers should act, disagreeing ones drop to the lead"
[ "$(wc -l < $W/home/brain-loop/spend.jsonl)" = 3 ] || fail "spend not logged per call"
out=$(bl grade $A --write); echo "    $out"
printf '%s\n' "$out" | grep -q "50% over 3 directions (3 sent to the sonnet check)" || fail "grade: low-confidence Jev answers not checked"
grep -q "^## Compliance grade" $A && grep -q "D1 \[partly, sonnet (jev said followed 0.40)" $A || fail "grade not written into the plan"
[ "$(tail -n +2 $W/home/compliance.tsv | wc -l)" = 3 ] || fail "compliance.tsv"
bl grade weekly --write | grep -q "acme-site: 50% of 3 directions" || fail "weekly"
grep -q "Most missed" $W/vault/lessons/plan-compliance-misses.md || fail "weekly rule note"
kill $JEV
ok "fake Jev: hybrid acts when sure, drops disagreements to the lead, logs spend per call; grade sends unsure answers to the Claude check"

# --- MCP server over stdio
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"brain_open","arguments":{"limit":5}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"brain","arguments":{"entity":"Lee"}}}' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope","arguments":{}}}' | bl mcp)
[ "$(printf '%s\n' "$out" | wc -l)" = 5 ] || fail "mcp: expected 5 replies: $out"
printf '%s\n' "$out" | jq -s -e '.[0].result.serverInfo.name == "brain-loop" and (.[1].result.tools | map(.name) | sort == ["brain","brain_mark","brain_open"])
  and (.[2].result.content[0].text | fromjson | .items | length == 5) and (.[3].result.content[0].text | fromjson | .id == "lee-placeholder")
  and .[4].error.code == -32602' >/dev/null || fail "mcp replies: $out"
ok "MCP stdio: initialize, tools/list, brain_open, brain, unknown tool"

# --- /brain page
bl page --port 8798 >/dev/null & PG=$!; sleep 1
python3 - <<'EOF' || fail "page routes"
import json, urllib.request, urllib.error
g = lambda p: urllib.request.urlopen("http://127.0.0.1:8798" + p, timeout=5).read().decode()
assert "<title>Brain</title>" in g("/brain/")
assert len(json.loads(g("/brain/graph.json"))["nodes"]) > 20
assert "open items" in g("/brain/open.txt?n=3")
assert json.loads(g("/brain/note?id=acme-site"))["frontmatter"]["type"] == "project"
assert json.loads(g("/brain/entity?q=dana"))["id"] == "dana-example"
try:
    g("/brain/note?id=nope"); raise SystemExit(1)
except urllib.error.HTTPError as e:
    assert e.code == 404
EOF
kill $PG
ok "/brain page: html, graph.json, open.txt, note, entity, 404"

# --- SessionStart hook
echo "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$W/lead\"}" | bl hook session-start | jq -e '.hookSpecificOutput.additionalContext | test("open items")' >/dev/null || fail "hook: lead"
echo "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$W/acme-site\"}" | bl hook session-start | grep -q "Brain note: acme-site" || fail "hook: tab"
[ -z "$(echo '{"hook_event_name":"SessionStart","cwd":"/tmp"}' | bl hook session-start)" ] || fail "hook spoke for an unknown folder"
[ -z "$(echo 'not json' | bl hook session-start)" ] || fail "hook broke on bad input"
ok "hook: open items for the lead, the project note for a tab, silent otherwise"

# --- stuck-check: the latest needs-human report and overdue checkpoints, each raised once
bl stuck; bl stuck
[ "$(said '\[STUCK')" = 1 ] && grep -q "\[STUCK >20 min\] beta-app is needs-human" $W/said.txt || fail "stuck report not raised exactly once"
[ "$(said 'CHECKPOINT OVERDUE')" = 2 ] && grep -q "CP2 (due 2026-10-14T18:00 UTC)" $W/said.txt || fail "overdue checkpoints not raised exactly once each"
grep -q "CP3" $W/said.txt && fail "a future checkpoint was raised"
ok "stuck-check raises a stuck report and each overdue checkpoint once (not future or template ones)"

# --- installer round trip
sh mods/install.sh brain-loop >/dev/null
S=$HOME/.claude/settings.json
jq -e '.hooks.SessionStart[0].hooks[0].command | endswith("brain-loop hook session-start")' $S >/dev/null || fail "install: hook"
$HOME/.local/bin/brain-loop help | grep -q "brain-loop build" || fail "install: command"
sh mods/install.sh brain-loop >/dev/null
[ "$(jq '.hooks.SessionStart | length' $S)" = 1 ] || fail "re-install duplicated the hook"
sh mods/install.sh brain-loop --uninstall >/dev/null
jq -e '.hooks.SessionStart == null' $S >/dev/null && [ ! -e $HOME/.local/bin/brain-loop ] || fail "uninstall"
ok "mods/install.sh brain-loop installs, re-installs without duplicates, uninstalls"

echo "brain-loop test: $n checks passed"
