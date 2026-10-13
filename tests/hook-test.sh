#!/bin/sh
# Checks the optional lead hook: blocks worker subagents in the lead's folder, allows READ-ONLY ones and other folders.
#   sh tests/hook-test.sh      (needs jq)
cd "$(dirname "$0")/.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.local/bin" "$T/lead" && cp bin/lk-config "$T/.local/bin/" && echo "LK_LEAD_DIR=$T/lead" > "$T/cfg"
run() { printf '%s' "$1" | HOME=$T LK_CONFIG=$T/cfg sh hooks/lead-no-worker-agents.sh >/dev/null 2>&1; echo $?; }
[ "$(run "{\"cwd\":\"$T/lead\",\"tool_input\":{\"prompt\":\"build it\"}}")" = 2 ] || { echo "FAIL: lead worker not blocked"; exit 1; }
[ "$(run "{\"cwd\":\"$T/lead\",\"tool_input\":{\"prompt\":\"READ-ONLY audit\"}}")" = 0 ] || { echo "FAIL: READ-ONLY blocked"; exit 1; }
[ "$(run "{\"cwd\":\"$T\",\"tool_input\":{\"prompt\":\"build it\"}}")" = 0 ] || { echo "FAIL: tab blocked"; exit 1; }
echo "hook test passed"
