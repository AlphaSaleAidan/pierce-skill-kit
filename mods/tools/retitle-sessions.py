#!/usr/bin/env python3
"""Backfill topic titles for past Claude sessions: Haiku names the topic from each session's
first + latest user prompts; the title is appended as an ai-title record (last one wins).
Skips sessions touched in the last 15 min (live ones title themselves via agent-board).
Usage: retitle-sessions.py [--dry] [--limit N]   (try --dry --limit 5 first; each title is one small Haiku call)."""
import json, os, subprocess, sys, time, glob
from concurrent.futures import ThreadPoolExecutor

CFG = os.environ.get('CLAUDE_CONFIG_DIR') or os.path.expanduser('~/.claude')
ROOT = os.path.join(CFG, 'projects')
DRY = '--dry' in sys.argv

def prompts(path):
    out = []
    for line in open(path, errors='replace'):
        if '"type":"user"' not in line: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('isMeta') or m.get('isSidechain'): continue
        c = m.get('message', {}).get('content')
        if isinstance(c, list): c = ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text')
        if not isinstance(c, str): continue
        c = c.strip()
        if not c or c.startswith(('<', '/', 'Caveat:', '[Request interrupted')): continue
        out.append(' '.join(c.split())[:300])
    return out

def title_for(ps):
    pick = ps[:1] + ps[-5:] if len(ps) > 6 else ps
    q = ('Name what this Claude Code session was about in 3-6 plain words, Title Case. Weight the LATEST requests most. '
         'Reply with the title only.\n\nRequests, oldest first:\n' + '\n'.join(f'{i+1}. {p}' for i, p in enumerate(pick)))
    env = {**os.environ, 'CLAUDE_CODE_PLUGIN_DIRS': ''}
    r = subprocess.run(['claude', '-p', '--model', 'haiku', '--strict-mcp-config', '--tools', '', '--no-session-persistence'],
                       input=q, capture_output=True, text=True, timeout=90, env=env, cwd='/tmp')
    t = r.stdout.strip().splitlines()[-1].strip().strip('"\'.') if r.stdout.strip() else ''
    return t[:60] if 2 <= len(t.split()) <= 9 else ''

def one(path):
    sid = os.path.basename(path)[:-6]
    if time.time() - os.path.getmtime(path) < 900: return 'live', sid, ''
    ps = prompts(path)
    if not ps: return 'empty', sid, ''
    t = title_for(ps)
    if not t: return 'fail', sid, ''
    if not DRY:
        with open(path, 'a') as f: f.write(json.dumps({'type': 'ai-title', 'aiTitle': t, 'sessionId': sid}) + '\n')
    return 'ok', sid, t

files = sorted(glob.glob(f'{ROOT}/*/*.jsonl'), key=os.path.getmtime, reverse=True)
if '--limit' in sys.argv: files = files[:int(sys.argv[sys.argv.index('--limit') + 1])]
counts = {}
with ThreadPoolExecutor(3) as ex:  # ponytail: 3 at once keeps the box calm (~8s and ~150MB per call)
    for status, sid, t in ex.map(one, files):
        counts[status] = counts.get(status, 0) + 1
        if t: print(f'{sid[:8]}  {t}', flush=True)
print(counts)
