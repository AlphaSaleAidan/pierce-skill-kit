#!/usr/bin/env python3
"""Deck pass rule over judge.json -> prints PASS/FAIL line, writes the fix list (worst first).
Pass = mean >= 8.5, every capture >= 7, no KILL. Thresholds: tune against decks you accepted vs rejected.
Usage: verdict.py judge.json fixlist.md   |   verdict.py --selftest"""
import json, sys
MEAN, MIN = 8.5, 7.0

def verdict(rows):
    rows = [r for r in rows if r.get('judge')]
    if not rows: return 'FAIL no judge output', []
    t = [r['judge']['total'] for r in rows]
    kills = [r for r in rows if r['judge']['kill']]
    mean, low = sum(t) / len(t), min(t)
    ok = mean >= MEAN and low >= MIN and not kills
    worst = sorted(rows, key=lambda r: r['judge']['total'])
    return f"{'PASS' if ok else 'FAIL'} mean {mean:.1f} (>= {MEAN}) · min {low} (>= {MIN}) · kills {len(kills)}", worst

if sys.argv[1] == '--selftest':
    mk = lambda i, t, k=(): {'id': i, 'judge': {'total': t, 'kill': list(k), 'defects': []}}
    assert verdict([mk('a', 9), mk('b', 8.2)])[0].startswith('PASS')
    assert verdict([mk('a', 9.5), mk('b', 6.9)])[0].startswith('FAIL')          # one weak slide
    assert verdict([mk('a', 9), mk('b', 9, ['Text-only slide'])])[0].startswith('FAIL')  # kill
    assert verdict([])[0].startswith('FAIL')
    print('selftest PASS'); sys.exit()
line, worst = verdict(json.load(open(sys.argv[1])))
with open(sys.argv[2], 'w') as f:
    for r in worst:
        a = r['judge']
        if a['total'] >= 8.5 and not a['kill']: continue
        tag = 'REBUILD' if a['kill'] else 'FIX'
        f.write(f"## {r['id'].split('__')[-1]} — {a['total']}/10 — {tag}{' — KILL: ' + ', '.join(a['kill']) if a['kill'] else ''}\n")
        f.write(''.join(f"- {d}\n" for d in a['defects']) + '\n')
print(line)
