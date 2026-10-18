"""brain-loop - the Obsidian + Opus + Jev loop. Run it through bin/brain-loop (it loads the kit config).

  brain-loop build                         (re)write the vault + .brain.json from the ledgers
  brain-loop open [N]                      open items in chase order (what the lead sees at SessionStart)
  brain-loop show NAME                     one note: a project, person, ask, decision or plan (fuzzy)
  brain-loop mark ID [--status S] [--owner O] [--chase YYYY-MM-DD] [--note T] [--link a,b] [--title T]
  brain-loop route dryrun|shadow|run|score|preview ...     report triage (brain-loop route help)
  brain-loop grade PLAN.md ... [--dry] [--write] | weekly  plan compliance grading (brain-loop grade)
  brain-loop plan-new PROJECT TASK [TAB]   start a plan from the tab-plan template, prints its path
  brain-loop mcp                           MCP server on stdio (brain, brain_open, brain_mark)
  brain-loop page [--port 8790]            the /brain graph page on 127.0.0.1
  brain-loop hook session-start            Claude Code SessionStart hook (reads JSON on stdin)
  brain-loop stuck                         re-raise stuck reports + overdue plan checkpoints to the lead
"""
import json
import os
import re
import sys
from pathlib import Path

from . import common as C


def _opt(a, name):
    return a[a.index(name) + 1] if name in a and a.index(name) + 1 < len(a) else None


def plan_new(project, task, tab=None):
    cfg = Path(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"))
    here = Path(__file__).resolve().parent.parent
    cands = [os.environ.get("BRAIN_PLAN_TEMPLATE", ""), cfg / "skills/tab-plan/template.md",
             here.parent.parent / "skills/tab-plan/template.md"]
    tpl = next((Path(c) for c in cands if c and Path(c).is_file()), None)
    if not tpl:
        raise SystemExit("plan-new: no template (install the tab-plan skill or set BRAIN_PLAN_TEMPLATE)")
    proj, t = C.slug(project, 40), C.slug(task, 40)
    p = C.PLANS / proj / f"{C.NOW.strftime('%m%d')}-{t}.md"
    if p.exists():
        raise SystemExit(f"plan-new: {p} already exists (follow-ups go in it as a new UPDATE section)")
    p.parent.mkdir(parents=True, exist_ok=True)
    text = tpl.read_text()
    for k, v in {"PROJECT": proj, "TASK": task, "TAB": tab or proj, "DATE": C.NOW.strftime("%Y-%m-%dT%H:%M")}.items():
        text = text.replace("{{" + k + "}}", v)
    p.write_text(text)
    print(p)


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "help"
    if cmd == "build":
        from .vault import Brain
        print(json.dumps(Brain().build()))
    elif cmd == "open":
        from .vault import Vault
        print(Vault().load().open_text(int(a[1]) if len(a) > 1 else 30))
    elif cmd == "show" and len(a) > 1:
        from .vault import Vault
        r = Vault().load().brain(" ".join(a[1:]))
        print(json.dumps({k: v for k, v in r.items() if k != "note"}, indent=1)[:3000])
        print(r.get("note", "")[:6000])
    elif cmd == "mark" and len(a) > 1:
        from .vault import Vault
        r = Vault().load().mark(a[1], status=_opt(a, "--status"), owner=_opt(a, "--owner"), chase_after=_opt(a, "--chase"),
                                note=_opt(a, "--note"), link=_opt(a, "--link"), title=_opt(a, "--title"))
        print(json.dumps(r))
        sys.exit(0 if r.get("ok") else 1)
    elif cmd in ("route", "grade"):
        from . import grade, jev, router
        try:
            (router if cmd == "route" else grade).main(a[1:])
        except jev.GateClosed as e:
            raise SystemExit(f"brain-loop {cmd}: {e}")
    elif cmd == "plan-new" and len(a) > 2:
        plan_new(a[1], a[2], a[3] if len(a) > 3 else None)
    elif cmd == "mcp":
        from . import server
        server.mcp()
    elif cmd == "page":
        from . import server
        server.page(int(_opt(a, "--port") or 8790))
    elif cmd == "hook":
        from . import hook
        hook.main(a[1:])
    else:
        print(re.sub(r"^\s*\n", "", __doc__))


if __name__ == "__main__":
    main()
