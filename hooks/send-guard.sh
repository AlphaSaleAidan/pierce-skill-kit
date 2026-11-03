#!/bin/sh
# Hook for your send/post tools (mail, Slack, SMS connectors). Register it on PreToolUse AND PostToolUse with the
# tools' names as the matcher (mods/install.sh hook send-guard '<tool names>' does both). Before a send it refuses:
#  - any link in the message that hasn't passed `link-check` in the last LK_LINK_FRESH_MIN minutes (exact URL), and
#  - the identical send (same tool, same input) already made in the last LK_SEND_DUP_MIN minutes (default 1440).
# After a send it records it, so a retry or a second script can't double-post. Needs jq.
. "$HOME/.local/bin/lk-config"
in=$(cat)
ev=$(printf '%s' "$in" | jq -r '.hook_event_name // "PreToolUse"')
h=$(printf '%s' "$in" | jq -cS '[.tool_name, .tool_input]' | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)
log=$LK_HOME/sends.tsv; [ -f "$log" ] || printf 'epoch\tsha\n' > "$log"
if [ "$ev" = PostToolUse ]; then printf '%s\t%s\n' "$(date +%s)" "$h" >> "$log"; exit 0; fi
deny() { jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'; exit 0; }
since=$(( $(date +%s) - ${LK_SEND_DUP_MIN:-1440} * 60 ))
awk -F'\t' -v h="$h" -v s="$since" '$2 == h && $1 >= s { f = 1 } END { exit !f }' "$log" &&
  deny "BLOCKED: this exact message was already sent in the last ${LK_SEND_DUP_MIN:-1440} min. Check the target before sending again; never re-send to 'make sure'."
miss=
for u in $(printf '%s' "$in" | jq -r '.tool_input | .. | strings' | grep -oE 'https?://[^][ "<>()]+' | sed 's/[.,;:!?]*$//' | sort -u); do
  "$HOME/.local/bin/link-check" --fresh "$u" || miss="$miss $u"
done
[ -z "$miss" ] || deny "BLOCKED: these links have no recent link-check pass:$miss. Run: link-check <url> \"<text the page must show>\" for each (a real browser, logged out), fix any that fail, then send."
exit 0
