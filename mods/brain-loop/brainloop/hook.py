"""Claude Code SessionStart hook: put the brain in front of a session before it starts work.

  the lead (session started in $LK_LEAD_DIR)  -> the open items, top 15 in chase order
  a project tab                               -> its project note's open items, if the folder name matches a project
Reads the vault files directly; if anything is missing or broken it prints nothing (never blocks a session).
Registered by `mods/install.sh brain-loop` as: brain-loop hook session-start
"""
import json
import os
import sys

from . import common as C
from .vault import Vault


def emit(text):
    if text.strip():
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": (
            "BRAIN (auto-loaded from the vault; cite note ids, newest wins):\n" + text)[:9000]}}))


def session_start(d):
    cwd = os.path.realpath(d.get("cwd") or os.getcwd())
    v = Vault().load()
    if not v.nodes:
        return
    if C.LEAD_DIR and cwd == os.path.realpath(str(C.LEAD_DIR)):
        emit(v.open_text(15) + "\n\nBefore answering the owner or closing a round: brain_open() for the full list, "
             "brain(name) for any project or person they mention.")
        return
    nid = v.alias.get(C.compact(os.path.basename(cwd)))  # exact name/alias only: no fuzzy guess for a tab
    if nid and v.nodes[nid]["type"] == "project":
        note = v.brain(nid)
        items = note.get("open_items", [])
        emit(f"## Brain note: {note['id']} ({note['path']}), {len(items)} open items\n" +
             "\n".join(f"- [{o.get('status')}|owner {o.get('owner')}|chase {o.get('chase_after')}] {o['title']} ({o['id']})"
                       for o in items[:8]))


def main(a):
    try:
        d = json.load(sys.stdin)
        if (a[:1] or ["session-start"])[0] == "session-start":
            session_start(d)
    except Exception:
        return  # never get in the way of a session
