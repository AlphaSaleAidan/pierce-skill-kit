#!/bin/sh
# Checks the optional lead hook: blocks worker subagents in the lead's window only; allows READ-ONLY ones, project
# tabs, and a plain Claude started in the lead's folder.   sh tests/hook-test.sh   (needs jq and tmux)
cd "$(dirname "$0")/.." || exit 1
for t in tmux jq; do command -v $t >/dev/null || { echo "hook test skipped: no $t"; exit 0; }; done
T=$(mktemp -d); S=psk-hook-$$; trap 'tmux -L $S kill-server 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/.local/bin" "$T/bin" "$T/lead" && cp bin/lk-config "$T/.local/bin/" && echo "LK_LEAD_DIR=$T/lead" > "$T/cfg"
printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$(command -v tmux)" "$S" > "$T/bin/tmux"; chmod +x "$T/bin/tmux"   # private tmux server
PATH=$T/bin:$PATH; export PATH
tmux new-session -d -s hub -n Lead -c "$T/lead"; tmux new-window -d -t hub: -n alpha; tmux new-session -d -s other -c "$T/lead"
pane() { tmux display -p -t "$1" '#{pane_id}'; }
run() { printf '%s' "$2" | HOME=$T LK_CONFIG=$T/cfg TMUX_PANE=$1 sh hooks/lead-no-worker-agents.sh >/dev/null 2>&1; echo $?; }
lead=$(pane hub:Lead)
[ "$(run "$lead" '{"tool_input":{"prompt":"build it"}}')" = 2 ] || { echo "FAIL: lead worker not blocked"; exit 1; }
[ "$(run "$lead" '{"tool_input":{"prompt":"READ-ONLY audit"}}')" = 0 ] || { echo "FAIL: READ-ONLY blocked"; exit 1; }
[ "$(run "$(pane hub:alpha)" '{"tool_input":{"prompt":"build it"}}')" = 0 ] || { echo "FAIL: tab blocked"; exit 1; }
[ "$(run "$(pane other:)" '{"tool_input":{"prompt":"build it"}}')" = 0 ] || { echo "FAIL: a Claude in the lead folder but outside the lead window was blocked"; exit 1; }
[ "$(run '' '{"tool_input":{"prompt":"build it"}}')" = 0 ] || { echo "FAIL: blocked outside tmux"; exit 1; }
echo "hook test passed"
