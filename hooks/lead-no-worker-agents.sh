#!/bin/sh
# Optional PreToolUse hook (matcher: Agent|Task): keeps the LEAD a manager, not a worker. In the lead's folder
# ($LK_LEAD_DIR), Agent calls are blocked unless the prompt starts with READ-ONLY (cross-project research).
# Project work goes to that project's tab instead. Project tabs (other folders) are untouched.
# Needs jq.
. "$HOME/.local/bin/lk-config"
in=$(cat)
cwd=$(printf '%s' "$in" | jq -r '.cwd // ""')
[ "$(realpath "$cwd" 2>/dev/null)" = "$(realpath "$LK_LEAD_DIR")" ] || exit 0
t=$(printf '%s' "$in" | jq -r '.tool_input.subagent_type // ""')
case "$t" in Explore|claude-code-guide) exit 0;; esac
printf '%s' "$in" | jq -r '.tool_input.prompt // ""' | head -c 200 | grep -q 'READ-ONLY' && exit 0
echo "Lead rule: don't do project work with your own subagents. Brief the owning tab (claude-tab <dir> -n <Project>, or brief-send <tab> <brief.md>). Subagents here are only for cross-project READ-ONLY research: start the prompt with READ-ONLY." >&2
exit 2
