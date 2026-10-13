#!/usr/bin/env python3
# ponytail: one snapshot script, JSON out; the mod just renders it.
# Env: HUB_ROOTS (repo globs), HUB_CACHE (snapshot path), CLAUDE_CONFIG_DIR. PRs need `gh` logged in; services need `ss` (Linux).
import json, os, re, subprocess, time, glob

def sh(*a, cwd=None, t=20):
    try: return subprocess.run(a, cwd=cwd, capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception: return ""

now = time.time()
HOME = os.path.expanduser("~")
CFG = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
# HUB_ROOTS: colon-separated globs of git repos to list (default: every repo directly under your home)
ROOTS = [g for pat in os.environ.get("HUB_ROOTS", "~/*/.git").split(":") for g in glob.glob(os.path.expanduser(pat))]
OUT = os.environ.get("HUB_CACHE") or os.path.join(HOME, ".cache", "projects-hub.json")
tilde = lambda p: "~" + p[len(HOME):] if p.startswith(HOME) else p

def projects(days=14):
    out = []
    for g in ROOTS:
        d = os.path.dirname(g)
        ts = sh("git", "log", "-1", "--format=%ct", cwd=d, t=5)
        if not ts.isdigit() or now - int(ts) > days * 86400: continue
        dirty = len([l for l in sh("git", "status", "--porcelain", cwd=d, t=10).splitlines() if l])
        ahead = sh("git", "rev-list", "--count", "@{u}..HEAD", cwd=d, t=5)
        out.append({"name": tilde(d)[2:] if tilde(d).startswith("~/") else d, "dir": d, "branch": sh("git", "branch", "--show-current", cwd=d, t=5) or "detached",
                    "dirty": dirty, "ahead": int(ahead) if ahead.isdigit() else None, "age": int(now - int(ts))})
    return sorted(out, key=lambda p: p["age"])

def _tail(path):
    with open(path, 'rb') as f:
        f.seek(0, 2); f.seek(max(0, f.tell() - 262144))
        return f.read().decode(errors='replace')

def _title(tail):
    # Last name the session was given (custom rename beats AI title).
    for key in ('"customTitle":"', '"aiTitle":"'):
        i = tail.rfind(key)
        if i >= 0: return tail[i + len(key):].split('"', 1)[0]
    return ''

def _last_active(tail):
    # Time of the last real message; title lines carry no timestamp, so appending one doesn't bump it.
    i = tail.rfind('"timestamp":"')
    if i < 0: return None
    from datetime import datetime
    try: return datetime.fromisoformat(tail[i + 13:].split('"', 1)[0].replace('Z', '+00:00')).timestamp()
    except ValueError: return None

def _cwd(path):
    with open(path, 'rb') as f: head = f.read(65536).decode(errors='replace')
    i = head.find('"cwd":"')
    return head[i + 7:].split('"', 1)[0] if i >= 0 else ''

def sessions(limit=40):
    # Like /resume: the most recent sessions by name. Live ones come from Claude's registry;
    # headless `claude -p` jobs and subagent transcripts (they live a folder deeper) never show.
    live = {}
    for f in glob.glob(os.path.join(CFG, "sessions", "*.json")):
        try:
            r = json.load(open(f))
            if os.path.exists(f"/proc/{r['pid']}"): live[r["sessionId"]] = r
        except Exception: continue
    out = []
    for path in glob.glob(os.path.join(CFG, "projects", "*", "*.jsonl")):
        sid = os.path.basename(path)[:-6]
        if sid in live and live[sid].get("entrypoint") != "cli": continue
        try:
            tail = _tail(path); title, cwd, at = _title(tail), _cwd(path), _last_active(tail)
        except Exception: continue
        if not title or not cwd or not at: continue  # headless one-shots never get a title
        out.append({"id": sid, "title": title[:60], "cwd": cwd, "age": int(now - at), "live": sid in live})
    return sorted(out, key=lambda x: x["age"])[:limit]

def services():
    out = []
    for l in sh("ss", "-ltnpH").splitlines():
        m = re.search(r'users:\(\("([^"]*)",pid=(\d+)', l)
        if not m: continue
        name, pid = m.groups()
        port = l.split()[3].rsplit(":", 1)[-1]
        if not port.isdigit() or int(port) > 9999: continue
        if name in ("sshd", "systemd-resolve", "nginx", "cupsd"): continue
        try: cwd = tilde(os.readlink(f"/proc/{pid}/cwd"))
        except Exception: cwd = "?"
        out.append({"port": int(port), "proc": name, "cwd": cwd})
    seen, uniq = set(), []
    for s in sorted(out, key=lambda s: s["port"]):
        if s["port"] not in seen: seen.add(s["port"]); uniq.append(s)
    return uniq

def prs():
    raw = sh("gh", "search", "prs", "--author", "@me", "--state", "open", "--limit", "60",
             "--json", "repository,number,title,updatedAt,isDraft,url", t=30)
    try: items = json.loads(raw or "[]")
    except Exception: return []
    return [{"repo": p["repository"]["name"], "n": p["number"], "title": p["title"][:70],
             "draft": p["isDraft"], "updated": p["updatedAt"][:10], "url": p["url"]}
            for p in sorted(items, key=lambda p: p["updatedAt"], reverse=True)]

out = json.dumps({"at": int(now), "projects": projects(), "sessions": sessions(),
                  "services": services(), "prs": prs()})
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT + ".tmp", "w").write(out); os.replace(OUT + ".tmp", OUT)  # the statusline mod reads this
print(out)
