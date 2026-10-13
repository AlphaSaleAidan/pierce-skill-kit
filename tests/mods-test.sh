#!/bin/sh
# Mods installer round trip + hook behaviour, in a throwaway container:
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/mods-test.sh
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq jq >/dev/null
export HOME=/tmp/h; mkdir -p $HOME; cp -r /kit /tmp/kit; cd /tmp/kit
S=$HOME/.claude/settings.json
fail() { echo "FAIL: $*"; cat "$S"; exit 1; }
for m in agent-board model-map projects-hub; do sh mods/install.sh $m >/dev/null; done
sh mods/install.sh statusline >/dev/null
sh mods/install.sh hook lead-guard >/dev/null; sh mods/install.sh hook review-gate >/dev/null
sh mods/install.sh hook mail-no-links 'mcp__mail__send' >/dev/null
sh mods/install.sh agent-board >/dev/null   # re-install must not duplicate
[ "$(jq -r '.env.CLAUDE_CODE_PLUGIN_DIRS' $S | tr ':' '\n' | wc -l)" = 3 ] || fail "plugin dirs"
for m in agent-board model-map projects-hub; do test -f $HOME/.config/pierce-skill-kit/mods/$m/hooks/hooks.json || fail "$m not copied"; done
jq -e '.statusLine.command | endswith("statusline/statusline.sh")' $S >/dev/null || fail "statusline"
[ "$(jq '.hooks.PreToolUse | length' $S)" = 3 ] || fail "hooks"
echo '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"}}' | sh "$(jq -r '.statusLine.command' $S | cut -d' ' -f2)" | grep -q Opus || fail "statusline runs"
echo "ok: all mods installed, no duplicates, statusline runs"
echo '{"tool_input":{"body":"see https://example.com"}}' | sh $HOME/.config/pierce-skill-kit/hooks/mail-no-links.sh | grep -q deny || fail "mail hook"
echo '{"tool_input":{"command":"pm2 restart shop-api"}}' | REVIEW_GATED=shop-api REVIEW_MARKERS=/tmp sh $HOME/.config/pierce-skill-kit/hooks/review-gate.sh | grep -q deny || fail "review gate"
touch /tmp/review-ok-shop-api
[ -z "$(echo '{"tool_input":{"command":"pm2 restart shop-api"}}' | REVIEW_GATED=shop-api REVIEW_MARKERS=/tmp sh $HOME/.config/pierce-skill-kit/hooks/review-gate.sh)" ] || fail "review gate after review"
echo "ok: hooks block and allow correctly"
for m in agent-board model-map projects-hub statusline; do sh mods/install.sh $m --uninstall >/dev/null; done
for h in lead-guard review-gate mail-no-links; do sh mods/install.sh hook $h --uninstall >/dev/null; done
[ "$(jq -c . $S)" = '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":""},"hooks":{"PreToolUse":[]}}' ] || fail "uninstall left: $(jq -c . $S)"
echo "ok: uninstall removes everything"
echo "ALL MODS TESTS PASSED"
