#!/bin/sh
# Hook for the LEAD only (does nothing in project tabs): caps the hands-on shell commands the lead runs per turn,
# so it routes and decides instead of quietly doing a tab's work (quality falls when the lead juggles everything).
# Register on UserPromptSubmit (resets the count) and PreToolUse with matcher Bash (counts):
# mods/install.sh hook lead-cap does both. The lead's own tools (report, order, lead-*, tab-*, claude-tab,
# brief-send, link-check, git status/log/diff, ls, cat...) don't count. LK_LEAD_CMD_CAP (default 6) per turn.
# Needs jq.
. "$HOME/.local/bin/lk-config"
in=$(cat)
[ -n "$TMUX_PANE" ] && [ "$(tmux display -p -t "$TMUX_PANE" '#{session_name}:#{window_name}' 2>/dev/null)" = "$LK_LEAD" ] || exit 0
f=$LK_HOME/lead-cmds.$(printf '%s' "$in" | jq -r '.session_id // "s"' | tr -c 'A-Za-z0-9-' _)
[ "$(printf '%s' "$in" | jq -r '.hook_event_name // ""')" = UserPromptSubmit ] && { echo 0 > "$f"; exit 0; }
c=$(printf '%s' "$in" | jq -r '.tool_input.command // ""' | sed 's/^[[:space:]]*//')
case ${c%% *} in report|order|lead|lead-*|tab-*|claude-tab|brief-send|link-check|inbox-since|job|ls|cat|head|tail|grep|wc|date|tmux|pwd|echo) exit 0;; esac
case $c in "git status"*|"git log"*|"git diff"*|"git show"*|"gh pr view"*|"gh pr list"*|"gh run"*) exit 0;; esac
n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); echo $n > "$f"
[ $n -le "${LK_LEAD_CMD_CAP:-6}" ] && exit 0
echo "Lead rule: that's $n hands-on commands this turn (cap ${LK_LEAD_CMD_CAP:-6}). The lead routes, decides and verifies. Hand this to the owning tab, or the Ops tab for cross-project work: brief-send <tab> <brief.md>. The human can raise LK_LEAD_CMD_CAP." >&2
exit 2
