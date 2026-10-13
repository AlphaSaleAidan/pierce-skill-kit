#!/usr/bin/env bash
# Apply (or revert) the Pierce Skill Kit overlay on a project initialised with
# `npx ruflo@latest init`. Safe to run more than once.
#
#   ./apply.sh [PROJECT_DIR]           apply (default PROJECT_DIR = current dir)
#   ./apply.sh --revert [PROJECT_DIR]  put the backed-up upstream files back
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH="$HERE/config-dir.patch"
MARK="pierce-kit: honor CLAUDE_CONFIG_DIR"
FILES=(.claude/helpers/auto-memory-hook.mjs .claude/helpers/intelligence.cjs)

REVERT=0
if [ "${1:-}" = "--revert" ]; then REVERT=1; shift; fi
DIR="${1:-$PWD}"
cd "$DIR"

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "missing $DIR/$f - run 'npx ruflo@latest init' first" >&2; exit 1; }
done

if [ "$REVERT" = 1 ]; then
  for f in "${FILES[@]}"; do
    if [ -f "$f.pierce-kit.bak" ]; then mv -f "$f.pierce-kit.bak" "$f"; echo "restored $f"; fi
  done
  exit 0
fi

applied=0
for f in "${FILES[@]}"; do grep -qF "$MARK" "$f" && applied=$((applied + 1)); done
if [ "$applied" = "${#FILES[@]}" ]; then echo "overlay already applied"; exit 0; fi
if [ "$applied" != 0 ]; then echo "overlay half-applied; run --revert or re-init first" >&2; exit 1; fi

if command -v patch >/dev/null 2>&1; then
  try() { patch -p1 --forward --silent "$@" < "$PATCH"; }
elif command -v git >/dev/null 2>&1; then
  try() { if [ "${1:-}" = "--dry-run" ]; then git apply --check "$PATCH"; else git apply "$PATCH"; fi; }
else
  echo "need 'patch' or 'git' to apply the overlay" >&2; exit 1
fi

# Dry run first so a newer upstream that moved the code leaves files untouched.
if ! try --dry-run >/dev/null; then
  echo "patch does not fit this ruflo version; nothing changed (see README 'If the patch fails')" >&2
  exit 1
fi
for f in "${FILES[@]}"; do cp -p "$f" "$f.pierce-kit.bak"; done
try
echo "overlay applied (backups: *.pierce-kit.bak)"
