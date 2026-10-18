"""router: the "observe" step of the plan -> act -> observe -> improve loop.

Every new tab report ($LK_HOME/reports.tsv) is classified: needs_owner / blocked / done_proven / has_next /
urgency 0-2 / which plan + which of its rows (order ids). Confident results become mechanical writes (a plan
Progress log line, a brain_mark on the order's note, an order ledger note); anything less sure goes to the lead in
ONE batched message per run. The lead keeps the judgment calls.

Engines behind one shape: `stub` (rules, free, default), `jev` (gated, see jev.py) and `hybrid` (per field, a
confident source wins; two confident sources that disagree drop to the lead). Writes happen only with --apply.
Pause it any time: touch $BRAIN_ROUTER_DIR/OFF (cron keeps running and does nothing).

  brain-loop route dryrun [--last 200] [--engine E]    classify + proposed actions -> dryrun-E.jsonl (no writes)
  brain-loop route shadow [--engine E]                 new rows since the last run, logged only (cron)
  brain-loop route run --apply [--engine E] [--since LINE]   new rows since the last run, writes for real
  brain-loop route score GOLD.jsonl [RUN.jsonl]        field accuracy of a run vs a hand-labelled gold set
  brain-loop route preview LINE                        print the exact Jev request body for one report (no call)
"""
import csv
import hashlib
import json
import re
import sys
import time
from pathlib import Path

from . import common as C
from . import jev
from .vault import Vault, load_entities

OUT = C.ROUTER_DIR
STATE = OUT / "state.json"
OFF = OUT / "OFF"
DONE_KEYS = OUT / "applied.keys"  # one hash per action already applied: a replay never writes it again
ACT, CONFIRM = 0.9, 0.5  # >=0.9 act alone, 0.5-0.9 ask the lead, <0.5 do nothing
FIELDS = ("needs_owner", "blocked", "done_proven", "has_next", "urgency", "plan", "rows")


def _aliases():
    ents, _ = load_entities()
    m = {}
    for s, e in ents.items():
        if e["type"] == "project":
            for a in {s, e["title"], *e["aliases"]}:
                m[a.strip().lower()] = s
    return m


ALIAS = _aliases()


def norm(s):
    """A tab/project name in a report -> plan folder (an entity's aliases map to its slug)."""
    s = (s or "").strip().lower()
    return ALIAS.get(s, s.replace(" ", "-"))


def read_reports():
    try:
        with open(C.REPORTS, newline="") as f:
            rows = list(csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE))
    except FileNotFoundError:
        return []
    out = []
    for i, r in enumerate(rows[1:], start=2):
        r = (r + [""] * 6)[:6]
        out.append({"line": i, "time": C.date(r[0]), "project": r[1], "status": r[2], "message": r[3], "proof": r[4], "tab": r[5]})
    return out


# ---------------------------------------------------------------- plans
STAMP = re.compile(r"\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}|\d{2}-\d{2}T\d{2}:\d{2})\b")


def load_plans():
    plans = []
    for p in sorted(C.PLANS.glob("*/*.md")) if C.PLANS and C.PLANS.is_dir() else []:
        t = p.read_text(errors="ignore")
        m = re.search(r"^Status: ACTIVE \| Owner tab: ([^|]+)\|.*?Order: (.*)$", t, re.M)
        if not m:
            continue
        rows = {}
        for line in C.section(t, "Rows").splitlines():
            ids = re.match(r"-\s*([\d,\s]+)\|\s*(.*)", line)
            if ids:
                for n in re.findall(r"\d+", ids.group(1)):
                    rows[int(n)] = ids.group(2)
        opened = re.search(r"Opened:\s*([\d\-T:]+)", t)
        stamps = sorted(C.date(x) for x in STAMP.findall(C.section(t, "Progress log")))
        plans.append({"path": str(p), "dir": p.parent.name, "owner": m.group(1).strip(),
                      "orders": [int(n) for n in re.findall(r"#(\d+)", m.group(2))], "rows": rows,
                      "text": (C.section(t, "Goal") + " " + " ".join(rows.values())).lower(),
                      "opened": C.date(opened.group(1)) if opened else (stamps[0] if stamps else "")})
    return plans


WORD = re.compile(r"[a-z][a-z0-9.$-]{2,}")
STOP = set("the and for with that this from have will not are was but you your his its all any can now next done "
           "into than then them they what when been only also just more still each after before plan tab lead owner "
           "report needs row rows".split())


def words(s):
    return {w.strip(".-") for w in WORD.findall((s or "").lower())} - STOP


def match_plan(r, plans):
    """-> (plan path | 'none', conf, [row ids], row conf)"""
    keys = {norm(r["project"]), norm(r["tab"])}
    # a plan only covers reports written after it was opened
    cand = [p for p in plans if (p["dir"] in keys or norm(p["owner"]) in keys) and r["time"] >= p["opened"]]
    msg = r["message"]
    if not cand:
        return "none", 0.8, [], 0.8
    w = words(msg)
    if len(cand) > 1:
        scored = sorted(((len(w & words(p["text"])), i, p) for i, p in enumerate(cand)), key=lambda x: -x[0])
        plan, conf = scored[0][2], (0.7 if scored[0][0] > scored[1][0] else 0.5)
    else:
        plan, conf = cand[0], 0.9
    # rows: explicit "row 3" / "#3" first, else keyword overlap with each row's ask
    ids = [int(n) for n in re.findall(r"\brows? (\d+)", msg, re.I) if int(n) in plan["rows"]]
    ids += [o for o in (int(n) for n in re.findall(r"#(\d+)", msg)) if o in plan["rows"] and o not in ids]
    if ids:
        return plan["path"], conf, ids, 0.9
    hits = []
    for rid, ask in plan["rows"].items():
        ov = w & (words(ask) - words(plan["owner"]) - {plan["dir"]})
        if len(ov) >= 3:
            hits.append((len(ov), rid))
    hits.sort(reverse=True)
    ids = [rid for n, rid in hits if n >= max(3, hits[0][0] - 1)][:3] if hits else []
    return plan["path"], conf, ids, (0.6 if ids else 0.5)


# ---------------------------------------------------------------- stub classifier (rules)
ASK_OWNER = re.compile(r"\b((the )?(owner|human|you) (runs?|must|needs? to|to (send|sign|approve|pick|decide|confirm|press|run|open))|"
                       r"your (ok|call|go|approval|answer)|ok to (merge|deploy|send|ship|spend)|approve|go\?|"
                       r"which (one|option)|waiting (on|for) (the )?(owner|human|you)|press send|you sign)\b", re.I)
BLOCK = re.compile(r"\b(blocked|can'?t|cannot|won'?t let|stuck|waiting (on|for)|on hold|denied|refused|no access|"
                   r"needs? (a |the )?(key|login|token|access))\b", re.I)
URGENT = re.compile(r"\b(urgent|stop|asap|today|tonight|deadline|overdue|prod|down|broken|outage|charge|invoice|"
                    r"contract|legal|lawyer|client|refund|payment)\b|\$\d", re.I)
PROOF = re.compile(r"(https?://|(?<![\w/])(~|\.)?/[\w.\-]+/[\w.\-/]+|\.png\b|\.jpe?g\b|\b[0-9a-f]{7,40}\b|\bPR ?#\d+|\bcommit\b|"
                   r"\bcall[_ -]?id\b|\b\d+/\d+\b|\bcurl(ed)? 200\b|tests? (pass|green))", re.I)
CLAIM = re.compile(r"\b(done|shipped|built|live|merged|landed|passed|ready|delivered|deployed|verified|scores?|graded|"
                   r"curl(ed)? 200|green|fixed|drafted|wrote)\b", re.I)
PROSE_NEXT = re.compile(r"\b(next|meanwhile|continuing|then i|i'?ll|i will|running now|in progress|starting)\b", re.I)
FAILED_DONE = re.compile(r"\b(not (done|verified|live)|failed|couldn'?t|didn'?t work|still broken)\b", re.I)


def stub_classify(r, plans):
    st, msg, proof = r["status"].lower(), r["message"], r["proof"]
    o = {}
    if st == "needs-human":
        o["needs_owner"] = (True, 0.9 if ASK_OWNER.search(msg) or "?" in msg else 0.6)
    else:
        o["needs_owner"] = (True, 0.6) if ASK_OWNER.search(msg) else (False, 0.9)
    if st in ("blocked", "failed"):
        o["blocked"] = (True, 0.9)
    elif BLOCK.search(msg):
        o["blocked"] = (True, 0.5)
    else:
        o["blocked"] = (False, 0.9)
    if st == "done":
        real = bool(proof.strip()) or bool(PROOF.search(msg))
        o["done_proven"] = (real and not FAILED_DONE.search(msg), 0.9 if proof.strip() else 0.6)
    elif st in ("blocked", "failed"):
        o["done_proven"] = (False, 0.9)
    else:  # a finished piece inside a progress/needs-human report: true when claimed with proof, never acted on alone
        o["done_proven"] = (bool(CLAIM.search(msg) and (proof.strip() or PROOF.search(msg))), 0.6)
    if re.search(r"\bNEXT\s*:", msg):
        o["has_next"] = (True, 1.0)
    else:
        o["has_next"] = (True, 0.6) if PROSE_NEXT.search(msg) else (False, 0.9)
    u = 2 if URGENT.search(msg) else (1 if st in ("needs-human", "blocked", "failed") else 0)
    o["urgency"] = (u, 0.6)  # never confident: urgency never acts alone
    path, pc, ids, rc = match_plan(r, plans)
    o["plan"] = (path, pc)
    o["rows"] = (ids, rc)
    return o


# ---------------------------------------------------------------- jev classifier (gated)
def jev_questions(plans_for_choice):
    return {
        "needs_owner": {"type": "noul", "instructions": "Does this report require the owner (the human running these AI tabs) to decide, approve, sign, run, send or answer something?",
                        "criteria": {"true": "the owner must act or answer", "false": "FYI only, nothing for the owner to do"}},
        "blocked": {"type": "noul", "instructions": "Is the tab unable to proceed on its main work?",
                    "criteria": {"true": "main work stopped waiting on someone or a failure", "false": "work continues"}},
        "done_proven": {"type": "noul", "instructions": "Does it claim something finished AND give real proof (link, commit, screenshot path, test or call id)?",
                        "criteria": {"true": "finished with concrete proof", "false": "not finished, or no proof"}},
        "urgency": {"type": "score", "instructions": "How urgent is this for the owner?",
                    "criteria": ["informational", "needs attention soon (decision pending, blocked)",
                                 "money, legal, client-facing, live production or due today"]},
        "plan": {"type": "choice", "instructions": "Which plan does this report belong to?",
                 "criteria": {**{p["path"]: f"{p['owner']}: {p['text'][:160]}" for p in plans_for_choice},
                              "none": "no listed plan covers it"}},
    }


def jev_request(r, plans):
    keys = {norm(r["project"]), norm(r["tab"])}
    cand = [p for p in plans if p["dir"] in keys or norm(p["owner"]) in keys] or plans
    state = {k: r[k] for k in ("time", "project", "status", "message", "proof", "tab")}
    return state, jev_questions(cand)


def jev_classify(r, plans):
    a, usage = jev.decide(*jev_request(r, plans), what=f"report L{r['line']}")
    o = stub_classify(r, plans)  # has_next + rows stay rule-based (exact text checks)
    for k in ("needs_owner", "blocked", "done_proven"):
        p = float(a[k].get("noul", 0.5))
        o[k] = (p >= 0.5, abs(p - 0.5) * 2)
    u = a["urgency"]
    o["urgency"] = (int(round(float(u.get("score", 0)))), float(u.get("confidence", 0)))
    pl = a["plan"]
    o["plan"] = (pl.get("choice", "none"), float(pl.get("confidence", 0)))
    if o["plan"][0] == "none":
        o["rows"] = ([], o["plan"][1])
    o["_usage"] = usage
    return o


def hybrid_classify(r, plans):
    """Per field: a confident source wins; two confident sources that disagree drop to the lead; has_next and rows
    stay rule-led (exact text checks). On one operator's data Jev alone was weaker than the rules overall, but its
    >=0.9 answers were all right, so it wins only when sure."""
    s, j = stub_classify(r, plans), jev_classify(r, plans)
    o = {"_usage": j.get("_usage")}
    for k in FIELDS:
        (sv, sc), (jv, jc) = s[k], j[k]
        if k in ("has_next", "rows"):
            o[k] = s[k]
        elif sc >= ACT and jc >= ACT:
            o[k] = (sv, max(sc, jc)) if sv == jv else (sv if k == "plan" else jv, 0.6)
        elif jc >= ACT:
            o[k] = (jv, jc)
        elif sc >= ACT:
            o[k] = (sv, sc)
        else:
            o[k] = (jv, max(jc, sc)) if k in ("done_proven", "urgency") else (sv, max(jc, sc))
    if o["plan"][0] != s["plan"][0]:
        o["rows"] = ([], 0.5)
    return o


# ---------------------------------------------------------------- actions
def actions(r, c):
    """What the router would write. Each action: (kind, target, text, conf). Below ACT -> the lead instead."""
    acts = []
    plan, pc = c["plan"]
    short = re.sub(r"\s+", " ", r["message"])[:180]
    if plan != "none":
        acts.append(("plan_progress", plan, f"- {r['time']} [{r['status']}] {r['project']}: {short} (reports.tsv#L{r['line']})", pc))
        if c["needs_owner"][0]:
            # proposed only, never auto: the plan's Decisions section is curated by the lead
            q = re.split(r"(?<=\?)\s", r["message"])
            ask = next((s for s in q if s.strip().endswith("?")), short)[:200]
            acts.append(("plan_decision", plan, f"- {r['time'][:10]} {ask.strip()} -> (open; from reports.tsv#L{r['line']})",
                         min(pc, c["needs_owner"][1], 0.85)))
    for rid in c["rows"][0]:
        status = "done" if c["done_proven"][0] else ("waiting" if c["needs_owner"][0] else None)
        acts.append(("brain_mark", f"c-order-{rid}", json.dumps({"status": status, "note": f"{r['time']} {r['status']}: {short[:120]}"}),
                     min(c["rows"][1], c["done_proven"][1] if status == "done" else 1.0)))
    for oid in (int(n) for n in re.findall(r"\border ?#(\d+)", r["message"], re.I)):
        acts.append(("order_touch", str(oid), f"{r['time']} {r['status']}: {short[:100]}", 0.9))
    if not c["has_next"][0]:
        acts.append(("lead_chase", r["project"], "report has no NEXT: ask the tab what it does next", c["has_next"][1]))
    return acts


def route(acts):
    return [a for a in acts if a[3] >= ACT], [a for a in acts if CONFIRM <= a[3] < ACT]


def apply_action(a):
    """Write one action. Each write is idempotent: the same line is never added twice."""
    kind, target, text = a[:3]
    if kind in ("plan_progress", "plan_decision"):
        head = "## Progress log" if kind == "plan_progress" else "## Decisions needed"
        t = Path(target).read_text()
        m = re.search(rf"^{re.escape(head)}.*?$(.*?)(?=^## |\Z)", t, re.S | re.M)
        if not m or text in t:
            return False
        body = m.group(1).rstrip("\n")
        Path(target).write_text(t[:m.start(1)] + body + "\n" + text + "\n\n" + t[m.end(1):].lstrip("\n"))
        return True
    if kind == "brain_mark":
        d = json.loads(text)
        v = Vault().load()
        fm, _ = C.parse_fm(v.read(target))
        prev = re.match(r"\S+: (\d{4}-\d{2}-\d{2}T\d{2}:\d{2})", str(fm.get("my_note") or ""))
        if prev and prev.group(1) >= d["note"][:16]:
            return False  # the note already carries this report or a newer one
        return v.mark(target, status=d["status"], note=d["note"]).get("ok", False)
    if kind == "order_touch":
        try:
            rows = C.ORDERS.read_text().splitlines()
        except OSError:
            return False
        for i, line in enumerate(rows):
            f = line.split("\t")
            if f[0] == target:
                f = (f + [""] * 7)[:7]
                if text in f[6]:
                    return False
                f[6] = (f[6] + " | " if f[6] else "") + text
                rows[i] = "\t".join(f)
                C.ORDERS.write_text("\n".join(rows) + "\n")
                return True
        return False
    return False


def classify_all(reports, engine):
    plans = load_plans()
    fn = {"jev": jev_classify, "hybrid": hybrid_classify}.get(engine, stub_classify)
    out = []
    for r in reports:
        c = fn(r, plans)
        auto, lead = route(actions(r, c))
        out.append({"line": r["line"], "time": r["time"], "project": r["project"], "status": r["status"], "engine": engine,
                    **{k: c[k][0] for k in FIELDS}, "conf": {k: round(c[k][1], 2) for k in FIELDS},
                    "auto": [list(a[:3]) for a in auto], "lead": [list(a[:3]) for a in lead]})
    return out


def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {"line": len(read_reports()) + 1}  # first run starts at the end: never replays history


def run(engine, apply, since=None):
    OUT.mkdir(parents=True, exist_ok=True)
    if OFF.exists():
        print(json.dumps({"off": str(OFF)}))
        return
    st = load_state()
    if since is not None:
        st["line"] = since - 1
    reps = [r for r in read_reports() if r["line"] > st["line"]]
    try:
        res = classify_all(reps, engine)
    except (jev.GateClosed, OSError, ValueError, KeyError) as e:  # Jev down / gate closed: the rules still triage
        print(f"brain-loop route: {engine} failed ({e}); using stub", file=sys.stderr)
        engine = "stub"
        res = classify_all(reps, engine)
    log = OUT / ("applied.jsonl" if apply else "shadow.jsonl")
    ask = []  # one lead message per run, not one per report
    wrote = 0
    try:
        done = set(DONE_KEYS.read_text().split())
    except OSError:
        done = set()
    with open(log, "a") as f, open(DONE_KEYS, "a") as dk:
        for x in res:
            if apply:
                x["wrote"] = []
                for a in x["auto"]:
                    if a[0] == "lead_chase":
                        continue
                    k = hashlib.sha1(json.dumps(a).encode()).hexdigest()[:16]
                    x["wrote"].append(k not in done and apply_action(a))
                    if k not in done:
                        done.add(k)
                        dk.write(k + "\n")
                wrote += sum(x["wrote"])
                ask += [f"L{x['line']} {x['project']}: {a[2][:120]}" for a in x["auto"] if a[0] == "lead_chase"]
                ask += [f"L{x['line']} {x['project']}: confirm {a[0]} -> {Path(a[1]).name}" for a in x["lead"]
                        if a[0] != "plan_decision"]  # the report itself already reached the lead
            f.write(json.dumps(x) + "\n")
    if apply and ask:
        C.say(f"[brain-loop] {len(ask)} item(s) need your eye (reports.tsv lines): " + " | ".join(ask)[:900])
    if reps:
        st["line"] = reps[-1]["line"]
    STATE.write_text(json.dumps(st))
    print(json.dumps({"new": len(reps), "auto": sum(len(x["auto"]) for x in res), "lead": sum(len(x["lead"]) for x in res),
                      "wrote": wrote, "apply": apply, "engine": engine}))


def score(gold_path, run_path):
    gold = {g["line"]: g for g in map(json.loads, (x for x in open(gold_path) if x.strip()))}
    got = {x["line"]: x for x in map(json.loads, (x for x in open(run_path) if x.strip()))}
    tally = {k: [0, 0] for k in FIELDS}
    hi = {k: [0, 0] for k in FIELDS}  # accuracy on the items the router would act on alone
    miss = []
    for ln, g in gold.items():
        x = got.get(ln)
        if not x:
            continue
        for k in FIELDS:
            if k not in g:
                continue
            gv, xv = g[k], x[k]
            ok = sorted(gv) == sorted(xv) if k == "rows" else gv == xv
            tally[k][0] += ok
            tally[k][1] += 1
            if x["conf"][k] >= ACT:
                hi[k][0] += ok
                hi[k][1] += 1
            if not ok:
                miss.append((ln, k, gv, xv))
    print(f"{'field':12} {'all':>9}   {'conf>=0.9 (auto)':>18}")
    for k in FIELDS:
        a, n = tally[k]
        b, m = hi[k]
        print(f"{k:12} {a:>3}/{n:<3} {a / max(n, 1):4.0%}   {b:>3}/{m:<3} {b / max(m, 1):4.0%}")
    for ln, k, gv, xv in miss[:20]:
        print(f"  miss L{ln} {k}: gold {gv!r} got {xv!r}")
    return tally, hi, miss


def _opt(a, name, default=None, cast=str):
    return cast(a[a.index(name) + 1]) if name in a and a.index(name) + 1 < len(a) else default


def main(a):
    cmd = a[0] if a else "help"
    engine = _opt(a, "--engine", "stub")
    if cmd == "dryrun":
        OUT.mkdir(parents=True, exist_ok=True)
        t0 = time.time()
        res = classify_all(read_reports()[-_opt(a, "--last", 200, int):], engine)
        p = OUT / f"dryrun-{engine}.jsonl"
        p.write_text("".join(json.dumps(x) + "\n" for x in res))
        kinds = {}
        for x in res:
            for act in x["auto"]:
                kinds[act[0]] = kinds.get(act[0], 0) + 1
        print(json.dumps({"reports": len(res), "auto_actions": sum(len(x["auto"]) for x in res),
                          "lead_actions": sum(len(x["lead"]) for x in res), "auto_by_kind": kinds,
                          "reports_needing_lead": sum(1 for x in res if x["lead"]), "secs": round(time.time() - t0, 2), "out": str(p)}))
    elif cmd == "shadow":
        run(engine, apply=False, since=_opt(a, "--since", None, int))
    elif cmd == "run":
        run(engine, apply="--apply" in a, since=_opt(a, "--since", None, int))
    elif cmd == "score" and len(a) > 1:
        score(a[1], a[2] if len(a) > 2 and not a[2].startswith("--") else str(OUT / f"dryrun-{engine}.jsonl"))
    elif cmd == "preview" and len(a) > 1:
        r = next((x for x in read_reports() if x["line"] == int(a[1])), None)
        if not r:
            raise SystemExit(f"no report on line {a[1]}")
        print(json.dumps(jev.body(*jev_request(r, load_plans())), indent=1))
    else:
        print(__doc__)
