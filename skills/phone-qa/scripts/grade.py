#!/usr/bin/env python3
"""Programmatic grader for Vapi phone agents. Reads calls (free Vapi GETs, no metered spend), measures them
against PHONE-BAR.md's automatic checks, and writes a bundle a judge agent scores against the rubric.

usage: grade.py <assistantId | path/to/vapi.json> [--last N] [--since ISO] [--ids id1,id2] [--out DIR]
       grade.py --selftest
  vapi.json = {"assistantId": "...", "number": "+1..."}
env:  VAPI_API_KEY (required), VAPI_TESTER_NUMBER (E.164 of your AI-caller line; its calls get latency slack)
out: DIR (default ./runs/<target>-<mmdd-hhmm>)/calls.md + auto.json, prints a summary.
Exit 0 = zero auto defects, 1 = defects found."""
import json, os, re, sys, statistics, argparse, datetime, urllib.request, urllib.error
from pathlib import Path


def api(method, path, body=None):
    key = os.environ.get("VAPI_API_KEY") or sys.exit("set VAPI_API_KEY")
    req = urllib.request.Request("https://api.vapi.ai" + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> {e.code}: {e.read()[:400].decode(errors='replace')}")


# --- thresholds (PHONE-BAR.md "Hard numbers" — keep the two in sync) ---
LAT_P50_MS, LAT_P90_MS, LAT_MAX_MS = 1000, 1800, 3000   # real calls; AI-to-AI tests get +AI_SLACK_MS (their STT is slower)
AI_SLACK_MS = 500
MEAN_WORDS = 20                         # mean words per agent turn (greeting exempt)
GREETING_WORDS = 30
STOCK_ACKS = ("okay", "ok", "got it", "gotcha", "perfect", "alright", "great", "sure", "thanks", "thank you", "mhmm", "absolutely", "awesome")
MIN_ECHO = 0.5                          # share of reactive turns that reuse a word the caller just said (D2)
MAX_WORDS = 30                          # per agent turn (greeting exempt)
MAX_QUESTIONS = 1                       # per agent turn
MAX_NAME_USES = 2
MAX_FILLERS_PER_TURN = 1
BAD_ENDS = ("error", "failed", "pipeline", "exceeded")

ROBOTIC = [  # regex, label — tells a real receptionist never says
    (r"\bquestion (one|two|three|1|2|3)\b|\bnext question\b", "numbered questions"),
    (r"\blast 1\b", "'Last 1' (digit rendering)"),
    (r"\bi need to (collect|gather|ask you)\b|\bfor our records\b", "form language"),
    (r"\bi understand (your|how)\b.*\b(concern|frustrat)", "scripted empathy"),
    (r"\b(i apologize for the inconvenience|thank you for your patience)\b", "call-center boilerplate"),
    (r"\bis there anything else i can (help|assist)\b", "boilerplate close"),
    (r"\bas an ai\b|\blanguage model\b", "AI self-reference"),
    (r"^(certainly|absolutely|great question)[!.,]", "assistant-speak opener"),
    (r"\b(provide|furnish) (me with )?(your|the)\b", "formal ask"),
    (r"\bthank you for (that |sharing |providing )?(that )?information\b", "form thanks"),
    (r"\bplease (hold|bear with me|be advised)\b|\bmay i (please )?(have|get)\b", "formal phrasing"),
    (r"\bi('d| would) be (happy|glad) to (assist|help)\b|\bhow (may|can) i assist\b", "assistant-speak"),
    (r"\bjust to (double[- ]check|confirm)\b|\bsince you mentioned\b", "re-confirming a known fact"),
    (r"\b(firstly|secondly|lastly|in conclusion|to summarize)\b|[*_#`]|https?://", "written text in speech"),
]
# D8 hard gate: promises the prompt never authorized. Any hit fails the call.
PROMISES = [
    (r"\b(guarantee|guaranteed|promise)\b", "guarantee/promise"),
    (r"\bwithin (the next )?(\d+|an?|one|two|few) (minutes?|hours?|days?)\b", "invented timeframe"),
    (r"\b(same[- ]day|today|tonight|right away)\b.*\b(arrive|come out|be there|fix|send someone)\b", "invented arrival"),
    (r"\$\s?\d|\b\d[\d,]* dollars\b", "quoted a price"),
    (r"\b(we're|we are) (fully )?(licensed|insured|bonded|certified)\b", "unverified license claim"),
    (r"\binsurance (will|should) (cover|pay)\b", "insurance coverage claim"),
    (r"\bfree (estimate|inspection|quote|assessment)s?\b|\b(estimates?|inspections?) (are|is) free\b", "promised free (unapproved)"),
    (r"\bi'?m (a )?(real|human|real person)\b|\bi am (a )?(real|human)\b", "claimed to be human"),
]
FILLERS = r"\b(um+|uh+|okay so|let's see|alright so|hmm+)\b"


def calls_for(target, last, since, ids):
    if ids:
        return [api("GET", f"/call/{i}") for i in ids]
    aid = json.loads(Path(target).read_text())["assistantId"] if Path(target).is_file() else target
    cs = api("GET", f"/call?assistantId={aid}&limit={max(last, 1) if not since else 100}")
    if since:
        cs = [c for c in cs if c["createdAt"] >= since]
    return [c for c in cs if c.get("status") == "ended"][: None if since else last]


def questions(txt):
    """Real questions in a turn. Phone transcription splits one either/or question ("a repair? Or a replacement?")
    and tag-ons ("insurance? Like a storm or damage claim?") into several '?' — those count once."""
    segs = [x.strip() for x in re.split(r"(?<=[.?!])\s+", txt) if x.strip()]
    n, prev_q = 0, False
    for sg in segs:
        q = sg.endswith("?")
        tagon = prev_q and (re.match(r"(or|like|just|you know|either)\b", sg.lower()) or len(sg.split()) <= 5 or re.fullmatch(r"[\w\s,]+,? or [\w\s]+\?", sg))
        echo = len(sg.split()) <= 3 and n == 0 and segs.index(sg) == 0  # "Springfield?" read back first
        if q and len(sg.split()) > 1 and not tagon and not echo: n += 1  # "Okay?" / "Linda?" alone are not questions
        prev_q = q
    return n


def turns(c):
    out = []
    for m in c.get("messages") or c.get("artifact", {}).get("messages") or []:
        r = m.get("role")
        if r in ("bot", "assistant") and m.get("message"):
            out.append(("bot", m["message"].strip(), m.get("secondsFromStart", 0)))
        elif r == "user" and m.get("message"):
            out.append(("user", m["message"].strip(), m.get("secondsFromStart", 0)))
        elif r == "tool_calls":
            for t in m.get("toolCalls", []):
                out.append(("tool", t["function"]["name"], m.get("secondsFromStart", 0)))
    return out


def grade_call(c, schema_keys, first_message, first_message_since=""):
    T, d = turns(c), []
    bots = [t for t in T if t[0] == "bot"]
    # 1 latency
    lats = [x["turnLatency"] for x in (c.get("artifact", {}).get("performanceMetrics") or {}).get("turnLatencies", [])
            if x.get("turnLatency")]
    p50 = statistics.median(lats) if lats else None
    p90 = sorted(lats)[int(0.9 * (len(lats) - 1))] if lats else None
    tester = os.environ.get("VAPI_TESTER_NUMBER")
    slack = AI_SLACK_MS if tester and (c.get("customer") or {}).get("number") == tester else 0  # AI-caller line
    if lats and max(lats) > LAT_MAX_MS + slack: d.append(f"latency max {max(lats)}ms > {LAT_MAX_MS + slack}")
    if p50 and p50 > LAT_P50_MS + slack: d.append(f"latency p50 {p50:.0f}ms > {LAT_P50_MS + slack}")
    if p90 and p90 > LAT_P90_MS + slack: d.append(f"latency p90 {p90:.0f}ms > {LAT_P90_MS + slack}")
    # 2 greeting intact (phone transcription is lossy, so compare the first 3 words only)
    if first_message and bots and c["createdAt"] >= first_message_since:
        want = re.sub(r"[^a-z ]", "", first_message.lower()).split()[:3]
        got = re.sub(r"[^a-z ]", "", bots[0][1].lower()).split()[:3]
        if want != got: d.append(f"greeting clipped/garbled: heard '{' '.join(got)}' want '{' '.join(want)}'")
    # 3 per-turn checks
    openers, name_uses = {}, 0
    name = ((c.get("analysis") or {}).get("structuredData") or {}).get("caller_name")
    for i, (_, txt, t) in enumerate(bots):
        low = txt.lower()
        if i and len(txt.split()) == 1 and r"transfer" not in low: d.append(f"@{t:.0f}s one-word turn: \"{txt}\"")
        if i and len(txt.split()) > MAX_WORDS: d.append(f"@{t:.0f}s long turn ({len(txt.split())} words)")
        nq = questions(txt)
        if i and nq > MAX_QUESTIONS: d.append(f"@{t:.0f}s {nq} questions in one turn: \"{txt[:70]}\"")
        if len(re.findall(FILLERS, low)) > MAX_FILLERS_PER_TURN: d.append(f"@{t:.0f}s filler pile-up")
        for rx, lab in ROBOTIC:
            if re.search(rx, low): d.append(f"@{t:.0f}s robotic: {lab} — \"{txt[:60]}\"")
        for rx, lab in PROMISES:
            if re.search(rx, low): d.append(f"@{t:.0f}s GATE (D8) {lab} — \"{txt[:70]}\"")
        op = " ".join(re.sub(r"[^a-z ]", "", low).split()[:2])
        if i and op: openers[op] = openers.get(op, 0) + 1
        if name and len(name) > 1 and re.search(rf"\b{re.escape(name.lower())}\b", low): name_uses += 1
    sents = [x.strip().lower() for _, txt, _ in bots[1:] for x in re.split(r"(?<=[.?!])\s+", txt) if len(x.split()) > 3]
    for x in {x for x in sents if sents.count(x) > 1}: d.append(f"repeated sentence: \"{x[:60]}\"")
    if len(bots) > 4 and sum(1 for _, txt, _ in bots if re.search(FILLERS, txt.lower())) / len(bots) > 0.15:
        d.append("fillers in >15% of turns")
    for op, n in openers.items():
        if n >= 2: d.append(f"same opener '{op}' x{n}")
    body = [b for b in bots[1:]]
    if body and statistics.mean(len(x[1].split()) for x in body) > MEAN_WORDS:
        d.append(f"mean turn {statistics.mean(len(x[1].split()) for x in body):.0f} words > {MEAN_WORDS}")
    if bots and len(bots[0][1].split()) > GREETING_WORDS: d.append(f"greeting {len(bots[0][1].split())} words > {GREETING_WORDS}")
    acks = {}
    for _, txt, _ in body:
        m = re.match(r"\W*(" + "|".join(re.escape(a) for a in STOCK_ACKS) + r")\b", txt.lower())
        if m: acks[m.group(1)] = acks.get(m.group(1), 0) + 1
    for k, n in acks.items():
        if n > 1: d.append(f"stock ack '{k}' x{n} (max 1)")
    # D2 echo: after a caller turn, does the agent reuse one of the caller's content words?
    stop = set("that this with have what your just like yeah about there they them it's i'm don't know think".split())
    react, echo = 0, 0
    for a, b in zip(T, T[1:]):
        if a[0] == "user" and b[0] == "bot":
            uw = {w for w in re.findall(r"[a-z']{4,}", a[1].lower()) if w not in stop}
            if len(uw) >= 2:
                react += 1
                echo += bool(uw & set(re.findall(r"[a-z']{4,}", b[1].lower())))
    if react >= 3 and echo / react < MIN_ECHO: d.append(f"generic reactions: echoed the caller in {echo}/{react} turns (min {MIN_ECHO:.0%})")
    # name in two consecutive agent turns
    if name and len(name) > 1:
        hits = [bool(re.search(rf"\b{re.escape(name.lower())}\b", x[1].lower())) for x in bots]
        if any(x and y for x, y in zip(hits, hits[1:])): d.append("caller name in consecutive turns")
    if name_uses > MAX_NAME_USES: d.append(f"caller name used {name_uses}x (max {MAX_NAME_USES})")
    # 4 turn-taking: bot speaking twice in a row with no caller turn = double reply / split turn
    for a, b in zip(T, T[1:]):
        if a[0] == b[0] == "bot" and b[2] - a[2] < 8:
            d.append(f"@{b[2]:.0f}s double/split bot turn: \"{a[1][-40:]}\" + \"{b[1][:40]}\"")
    # 5 transfer right after a question with no caller answer in between
    for i, (r, txt, t) in enumerate(T):
        if r == "tool" and "transfer" in txt.lower():
            prev = [x for x in T[:i] if x[0] in ("bot", "user")]
            if prev and prev[-1][0] == "bot" and prev[-1][1].rstrip().endswith("?"):
                d.append(f"@{t:.0f}s transferred without waiting for the answer to: \"{prev[-1][1][-60:]}\"")
    # 6 caller lost: "hello?" mid-call = dead air
    hellos = sum(1 for r, txt, _ in T[1:] if r == "user" and re.search(r"\bhello\?", txt.lower()))
    if hellos: d.append(f"caller said 'Hello?' {hellos}x (dead air / lag)")
    # 7 ending
    er = c.get("endedReason", "")
    if any(b in er for b in BAD_ENDS): d.append(f"call ended badly: {er}")
    # 8 data capture (only for fields the caller plausibly reached — judge decides; we report gaps)
    sd = (c.get("analysis") or {}).get("structuredData") or {}
    missing = [k for k in schema_keys if not sd.get(k)]
    return {"id": c["id"], "created": c["createdAt"], "ended": er, "cost": c.get("cost"),
            "lat_p50": p50, "lat_p90": p90, "turns": len(bots), "defects": d,
            "data": sd, "missing_fields": missing, "transcript": T,
            "recording": (c.get("artifact") or {}).get("recordingUrl")}


def main():
    ap = argparse.ArgumentParser()
    if "--selftest" in sys.argv: return selftest()
    ap.add_argument("target"); ap.add_argument("--last", type=int, default=5)
    ap.add_argument("--since"); ap.add_argument("--ids"); ap.add_argument("--out")
    a = ap.parse_args()
    cs = calls_for(a.target, a.last, a.since, a.ids.split(",") if a.ids else None)
    if not cs: sys.exit("no ended calls found")
    asst = api("GET", f"/assistant/{cs[0]['assistantId']}")
    schema = (((asst.get("analysisPlan") or {}).get("structuredDataPlan") or {}).get("schema") or {}).get("properties", {})
    # greeting check only applies to calls placed since the assistant's last edit (older calls had older greetings)
    res = [grade_call(c, list(schema), asst.get("firstMessage", ""), asst.get("updatedAt", "")) for c in cs]
    tag = Path(a.target).parent.name if Path(a.target).is_file() else a.target
    out = Path(a.out or Path.cwd() / "runs" / f"{tag}-{datetime.datetime.now():%m%d-%H%M}")
    out.mkdir(parents=True, exist_ok=True)
    (out / "auto.json").write_text(json.dumps([{k: v for k, v in r.items() if k != "transcript"} for r in res], indent=2))
    md = [f"# {asst.get('name')} — {len(res)} calls\n"]
    for r in res:
        md.append(f"## {r['id']}  ({r['created'][:16]}, {r['ended']}, p50 {r['lat_p50']} p90 {r['lat_p90']}ms)")
        md.append("**Auto defects:** " + ("; ".join(r["defects"]) or "none"))
        md.append(f"**Data:** {json.dumps(r['data'])}  \n**Unfilled fields:** {', '.join(r['missing_fields']) or 'none'}\n")
        md += [f"- [{t:5.1f}s] **{role}**: {txt}" for role, txt, t in r["transcript"]] + [""]
    (out / "calls.md").write_text("\n".join(md))
    nd = sum(len(r["defects"]) for r in res)
    lat = [r["lat_p50"] for r in res if r["lat_p50"]]
    print(f"{len(res)} calls · {nd} auto defects · median p50 {statistics.median(lat) if lat else '-'}ms · "
          f"cost ${sum(r['cost'] or 0 for r in res):.2f} · {out}")
    for r in res:
        for x in r["defects"]: print(f"  {r['id'][:8]} {x}")
    sys.exit(1 if nd else 0)


def selftest():
    assert questions("What's the street address? When did you first notice the leak?") == 2
    assert questions("Is it a repair? Or a replacement?") == 1
    assert questions("Springfield? Great, and is it your home?") == 1
    msgs = [("bot", "Thanks for calling Acme Home Services, this is Sam. What's going on at the house?", 0),
            ("user", "My kitchen sink is leaking under the cabinet.", 3),
            ("bot", "A leak under the kitchen sink, that's no fun. What town are you in? And when did the leak first start?", 6),
            ("user", "Springfield.", 10),
            ("bot", "We guarantee someone today. It's $99 for a visit.", 12)]
    c = {"id": "t1", "createdAt": "2026-01-01T00:00:00Z", "endedReason": "customer-ended-call",
         "messages": [{"role": r, "message": m, "secondsFromStart": t} for r, m, t in msgs],
         "artifact": {"performanceMetrics": {"turnLatencies": [{"turnLatency": 900}, {"turnLatency": 2100}]}},
         "analysis": {"structuredData": {"caller_name": ""}}}
    r = grade_call(c, ["zip"], "Thanks for calling Acme", "")
    d = " | ".join(r["defects"])
    assert "2 questions" in d and "GATE (D8) guarantee" in d and "quoted a price" in d, d
    assert r["missing_fields"] == ["zip"] and r["lat_p50"] == 1500, r
    print("selftest PASS")


if __name__ == "__main__":
    main()
