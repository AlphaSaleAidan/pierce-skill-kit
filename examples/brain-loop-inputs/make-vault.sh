#!/bin/sh
# Rebuild examples/brain-vault from the fake inputs in this folder, with the brain-loop builder itself:
#   sh examples/brain-loop-inputs/make-vault.sh [out-dir]      (default: examples/brain-vault)
# "Now" is pinned so the output is the same on every machine; tests/brain-loop-test.sh diffs a fresh build against it.
in=$(cd "$(dirname "$0")" && pwd); kit=$(cd "$in/../.." && pwd)
out=${1:-$kit/examples/brain-vault}
LK_CONFIG=/dev/null LK_HOME=${LK_HOME:-$(mktemp -d)} BRAIN_VAULT=$out BRAIN_SOURCE_ROOT=$in BRAIN_NOW=2026-10-15T12:00 \
BRAIN_ENTITIES=$in/entities.json BRAIN_REPORTS=$in/reports.tsv BRAIN_ORDERS=$in/orders.tsv BRAIN_DECISIONS=$in/decisions.md \
BRAIN_PLANS=$in/plans BRAIN_MEMORY_DIRS=$in/memory BRAIN_LEDGER=$in/ledger.tsv \
  sh "$kit/mods/brain-loop/bin/brain-loop" build
