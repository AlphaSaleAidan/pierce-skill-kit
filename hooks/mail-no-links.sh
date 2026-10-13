#!/bin/sh
# PreToolUse hook: refuse a mail send/draft/reply whose body carries a link. Use it on a mail connector that rewrites
# links (some wrap every URL in a redirect that breaks), so a broken link physically can't go out that way.
# Set the hook's matcher to your connector's send/draft/reply tool names, e.g. "mcp__mail__send_message|mcp__mail__create_draft".
# Needs jq.
input=$(cat)
text=$(printf '%s' "$input" | jq -r '[.tool_input.body // "", .tool_input.htmlBody // "", .tool_input.text // ""] | join("\n")')
printf '%s' "$text" | grep -qiE 'https?://|www\.|href=' || exit 0
jq -n '{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: "BLOCKED: this mail tool rewrites links. Send links another way: create the draft through the mail API directly and fetch it back to check every link, or give the human the text to paste." } }'
