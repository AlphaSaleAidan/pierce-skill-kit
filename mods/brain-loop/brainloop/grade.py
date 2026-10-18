"""plan-grade: did the tab follow its plan's directions? (the "improve" step)

For each direction in a plan, gather evidence (that project's reports since the plan opened, the plan's Progress log
and Next steps, files named in proofs: exists / size / mtime), ask Jev followed / partly / not_followed, and send
answers below CONF to a headless Claude check (`claude -p --model sonnet`, no tools, hooks off, so it grades from
the evidence only). Directions come from the plan's "## Directions" section ("D1. <instruction> | proof: <...>");
a plan without one falls back to its Done-when items + Rules.

  brain-loop grade PLAN.md [PLAN.md ...] [--dry]   --dry: directions + evidence only, no model calls
  brain-loop grade PLAN.md --write                 also the plan's "## Compliance grade" + compliance.tsv
  brain-loop grade weekly [--write]                per-tab compliance % + most-missed directions (-> a brain rule note)
"""
import json
import os
import re
import shlex
import subprocess
import tempfile
import time
from pathlib import Path

from . import common as C
from . import jev
from . import router as jr

OUT = C.ROUTER_DIR / "plan-grade"
# lessons/ is not a folder the vault build manages, so its orphan cleanup never deletes this note
RULE_NOTE = C.VAULT / "lessons" / "plan-compliance-misses.md"
CONF = 0.7
VERDICTS = {"followed": "the evidence shows the direction was done as written (for a never/don't rule: no sign of a breach)",
            "partly": "some of it was done, or done without the proof the direction asked for",
            "not_followed": "not done, done differently, or a breach of the rule is shown"}


def directions(t):
    d = C.section(t, "Directions")
    out = []
    for m in re.finditer(r"^-?\s*D(\d+)\.\s*(.+?)(?:\s*\|\s*proof:\s*(.+))?$", d, re.M):
        if m.group(2).strip().startswith("<"):
            continue  # an unfilled template line
        out.append({"id": f"D{m.group(1)}", "text": m.group(2).strip(), "proof": (m.group(3) or "").strip(), "src": "Directions"})
    if out:
        return out
    n = 0
    for line in C.section(t, "Done when").splitlines():
        m = re.match(r"-\s*\[([ x])\]\s*(.+)", line)
        if m:
            n += 1
            out.append({"id": f"D{n}", "text": m.group(2).strip(), "proof": m.group(2).strip(), "src": "Done when",
                        "ticked": m.group(1) == "x"})
    for line in C.section(t, "Rules").splitlines():
        m = re.match(r"-\s*(.+)", line)
        if m:
            n += 1
            out.append({"id": f"D{n}", "text": m.group(1).strip(), "proof": "", "src": "Rules"})
    return out


PATH = re.compile(r"(?<![\w:/.~])(/[\w.@+\-]+(?:/[\w.@+\-]+)+)")


def file_facts(text):
    facts = []
    for p in dict.fromkeys(PATH.findall(text)):
        p = p.rstrip(".,;:)")
        if not C.allowed(p):
            continue
        if os.path.exists(p):
            st = os.stat(p)
            facts.append(f"FILE EXISTS {p} ({st.st_size} bytes, modified {time.strftime('%Y-%m-%dT%H:%M', time.gmtime(st.st_mtime))})")
        else:
            facts.append(f"FILE MISSING {p}")
    return facts


def evidence(plan_path, t):
    owner = re.search(r"Owner tab: ([^|]+)\|", t)
    keys = {Path(plan_path).parent.name, jr.norm(owner.group(1)) if owner else ""}
    log = C.section(t, "Progress log")
    opened = re.search(r"Opened:\s*([\d\-T:]+)", t)
    stamps = sorted(C.date(x) for x in jr.STAMP.findall(log))
    opened = C.date(opened.group(1)) if opened else (stamps[0] if stamps else "")
    reps = [r for r in jr.read_reports() if (jr.norm(r["project"]) in keys or jr.norm(r["tab"]) in keys) and r["time"] >= opened]
    lines = [f"REPORT {r['time']} [{r['status']}] {r['message']} {('| proof: ' + r['proof']) if r['proof'] else ''}" for r in reps]
    lines += [f"PLAN LOG {x.strip('- ')}" for x in log.splitlines() if x.strip()]
    lines += [f"PLAN NEXT {x.strip('- ')}" for x in C.section(t, "Next steps").splitlines() if x.strip()]
    return lines, reps, opened


def clip(x, head=300, tail=180):  # keep the end too: that's where NEXT: and the proof live
    return x if len(x) <= head + tail else x[:head] + " ... " + x[-tail:]


def pick(lines, d, k=12):
    w = jr.words(d["text"] + " " + d["proof"])
    scored = sorted(((len(w & jr.words(x)), -i, x) for i, x in enumerate(lines)), reverse=True)
    top = [x for s, _, x in scored[:k] if s > 0] or lines[-4:]
    return [clip(x) for x in top]


def ask_jev(d, ev):
    a, _ = jev.decide({"direction": d["text"], "proof_asked": d["proof"] or "(none named)", "evidence": ev},
                      {"verdict": {"type": "choice", "instructions": "Judge only from the evidence: did the tab follow this direction?",
                                   "criteria": VERDICTS}}, what=f"plan-grade {d['id']}")
    v = a["verdict"]
    return v.get("choice", "partly"), float(v.get("confidence", 0))


def ask_claude(d, ev):
    prompt = ("You grade whether an AI work tab followed one direction from its plan. Judge ONLY from the evidence below; "
              "do not assume work happened that the evidence doesn't show. For a never/don't rule, 'followed' means no sign "
              "of a breach.\n\nDIRECTION: " + d["text"] + "\nPROOF ASKED: " + (d["proof"] or "(none named)") +
              "\n\nEVIDENCE:\n" + "\n".join(ev) +
              '\n\nReply with one line of JSON only: {"verdict": "followed|partly|not_followed", "why": "<=25 words"}')
    cmd = shlex.split(C.CLAUDE_CMD) + ["-p", "--model", C.GRADE_MODEL, "--tools", "", "--no-session-persistence",
                                       "--setting-sources", "user", "--settings", '{"disableAllHooks": true}', prompt]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=180, cwd=tempfile.gettempdir()).stdout
        j = json.loads(re.search(r"\{.*\}", out, re.S).group(0))
        return j["verdict"], j.get("why", "")
    except (OSError, subprocess.SubprocessError, ValueError, AttributeError, KeyError) as e:
        return None, f"{C.GRADE_MODEL} check failed: {e}"


def grade(plan_path, write=False, dry=False):
    t = Path(plan_path).read_text()
    ds = directions(t)
    lines, reps, opened = evidence(plan_path, t)
    owner = (re.search(r"Owner tab: ([^|]+)\|", t) or [None, "?"])[1].strip()
    if dry:
        print(f"{plan_path}: {len(ds)} directions ({ds[0]['src'] if ds else 'none'}), {len(reps)} reports since {opened or '?'}")
        for d in ds:
            print(f"  {d['id']} [{d['src']}] {d['text']}" + (f" | proof: {d['proof']}" if d["proof"] and d["src"] == "Directions" else ""))
            for e in pick(lines, d, 3) + file_facts(d["proof"])[:3]:
                print(f"      {e}")
        return None, []
    jev.spend_check()
    rows = []
    for d in ds:
        ev = pick(lines, d) + file_facts(d["proof"] + " " + " ".join(r["proof"] for r in reps))[:8]
        verdict, conf = ask_jev(d, ev)
        by, why = "jev", ""
        if conf < CONF:
            sv, why = ask_claude(d, ev)
            if sv in VERDICTS:
                by = f"{C.GRADE_MODEL} (jev said {verdict} {conf:.2f})"
                verdict = sv
        rows.append({"date": time.strftime("%Y-%m-%dT%H:%M", time.gmtime()), "tab": owner, "plan": plan_path, "d": d["id"],
                     "src": d["src"], "text": d["text"], "verdict": verdict, "conf": round(conf, 2), "by": by, "why": why,
                     "evidence": " || ".join(ev[:3])[:600]})
    score = sum({"followed": 1, "partly": 0.5}.get(r["verdict"], 0) for r in rows) / max(len(rows), 1)
    md = [f"## Compliance grade ({rows[0]['date'] if rows else ''} UTC, plan-grade: Jev + {C.GRADE_MODEL} check below {CONF})",
          f"- Score: {score:.0%} over {len(rows)} directions"
          + (" (no Directions section yet: graded the Done-when items + Rules)" if ds and ds[0]["src"] != "Directions" else ""),
          f"- Evidence: {len(reps)} reports since {opened or '?'}, the plan's Progress log + Next steps, files named in proofs"]
    for r in rows:
        md.append(f"- {r['d']} [{r['verdict']}, {r['by']} {r['conf']}] {r['text'][:140]}" + (f" | why: {r['why']}" if r["why"] else ""))
    OUT.mkdir(parents=True, exist_ok=True)
    stem = Path(plan_path).parent.name + "-" + Path(plan_path).stem
    (OUT / f"{stem}.md").write_text("\n".join(md) + "\n")
    tsv = "".join("\t".join(str(r[k]).replace("\t", " ").replace("\n", " ") for k in
                            ("date", "tab", "plan", "d", "verdict", "conf", "evidence")) + "\n" for r in rows)
    (OUT / f"{stem}.tsv").write_text(tsv)
    if write:
        sec = "\n".join(md) + "\n"
        if re.search(r"^## Compliance grade", t, re.M):
            t = re.sub(r"^## Compliance grade.*?(?=^## |\Z)", lambda _: sec + "\n", t, flags=re.S | re.M)
        else:
            t = t.rstrip("\n") + "\n\n" + sec
        Path(plan_path).write_text(t)
        new = not C.COMPLIANCE.exists()
        with open(C.COMPLIANCE, "a") as f:
            if new:
                f.write("date\ttab\tplan\tDn\tverdict\tconfidence\tevidence\n")
            f.write(tsv)
    return score, rows


def weekly(write=False):
    try:
        rows = [x.split("\t") for x in C.COMPLIANCE.read_text().splitlines()[1:] if x.strip()]
    except FileNotFoundError:
        rows = []
    for p in OUT.glob("*.tsv") if not write else []:  # dry: include dry grades too
        rows += [x.split("\t") for x in p.read_text().splitlines() if x.strip()]
    tabs, missed = {}, {}
    for r in rows:
        if len(r) < 5:
            continue
        tab, plan, d, v = r[1], r[2], r[3], r[4]
        a = tabs.setdefault(tab, [0.0, 0])
        a[0] += {"followed": 1, "partly": 0.5}.get(v, 0)
        a[1] += 1
        if v != "followed":
            text = next((x["text"] for x in directions(Path(plan).read_text()) if x["id"] == d), d) if os.path.exists(plan) else d
            missed[text[:160]] = missed.get(text[:160], 0) + 1
    lines = ["# Plan compliance: most-missed directions", "",
             "Weekly from compliance.tsv (plan-grade). Tabs keep missing these; say them louder in new plans.", "",
             "## Per tab"] + [f"- {t}: {s / n:.0%} of {n} directions" for t, (s, n) in sorted(tabs.items())]
    lines += ["", "## Most missed"] + [f"- {n}x {t}" for t, n in sorted(missed.items(), key=lambda x: -x[1])[:15]]
    text = "\n".join(lines) + "\n"
    if write:
        RULE_NOTE.parent.mkdir(parents=True, exist_ok=True)
        old = RULE_NOTE.read_text() if RULE_NOTE.exists() else ""
        keep = old.split(C.GEN_END, 1)[1] if C.GEN_END in old else "\n"
        RULE_NOTE.write_text("---\ntype: rule\nsource: plan-grade weekly\n---\n" + C.GEN_START + "\n" + text + C.GEN_END + keep)
    print(text)


def main(a):
    write, dry = "--write" in a, "--dry" in a
    a = [x for x in a if x not in ("--write", "--dry")]
    if not a:
        print(__doc__)
    elif a[0] == "weekly":
        weekly(write)
    else:
        for p in a:
            score, rows = grade(os.path.abspath(p), write, dry)
            if score is not None:
                print(f"{p}: {score:.0%} over {len(rows)} directions "
                      f"({sum(1 for r in rows if r['by'] != 'jev')} sent to the {C.GRADE_MODEL} check)")
