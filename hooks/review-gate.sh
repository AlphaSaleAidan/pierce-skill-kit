#!/bin/sh
# PreToolUse hook on Bash: restarting or reloading an app that handles money needs a recent code review first.
# After a review passes:  touch "${REVIEW_MARKERS:-/tmp}/review-ok-<app>"   (valid REVIEW_MAX_AGE_MIN minutes, default 90)
# REVIEW_GATED = regex of app names, REVIEW_RESTART = regex of the restart command (default: pm2/systemctl restart|reload).
# Needs jq. With REVIEW_GATED unset it does nothing.
[ -n "$REVIEW_GATED" ] || exit 0
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
re=${REVIEW_RESTART:-'(pm2|systemctl) +(restart|reload)'}
app=$(printf '%s' "$cmd" | grep -oE "$re +($REVIEW_GATED)" | awk '{print $NF}' | head -1)
[ -z "$app" ] && exit 0
marker="${REVIEW_MARKERS:-/tmp}/review-ok-$app"
[ -f "$marker" ] && [ -n "$(find "$marker" -mmin "-${REVIEW_MAX_AGE_MIN:-90}" 2>/dev/null)" ] && exit 0
jq -n --arg app "$app" --arg m "$marker" '{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("BLOCKED: " + $app + " handles money and has no recent review. Run an independent reviewer on the current diff; if it passes, touch " + $m + ", then retry.") } }'
