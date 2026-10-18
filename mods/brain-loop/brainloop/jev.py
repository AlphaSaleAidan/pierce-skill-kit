"""Jev (a small decision model on OpenRouter's decisions API) behind a spend gate.

The gate is closed until you set BRAIN_JEV_CAP_USD (a monthly dollar cap). Every call is logged to
$BRAIN_ROUTER_DIR/spend.jsonl; the month stops at the cap and the lead is told once when a day passes
BRAIN_JEV_DAY_ALERT_USD (default: a tenth of the cap). The key is read from LK_CHECK_KEY_FILE
(OPENROUTER_API_KEY=...), the same file report-check uses. Measured: about $0.00004 per report call.
"""
import json
import time
import urllib.request

from . import common as C

SPEND = C.ROUTER_DIR / "spend.jsonl"
EST_COST = 0.00005  # per call when the API doesn't return a cost


class GateClosed(Exception):
    pass


def spent(prefix):
    try:
        return sum(x["cost"] for x in map(json.loads, open(SPEND)) if x["day"].startswith(prefix))
    except FileNotFoundError:
        return 0.0


def spend_check():
    if C.JEV_CAP <= 0:
        raise GateClosed("Jev spend gate closed: set BRAIN_JEV_CAP_USD (monthly $ cap) in the config, or use --engine stub")
    today = time.strftime("%Y-%m-%d", time.gmtime())
    if spent(today[:7]) >= C.JEV_CAP:
        raise GateClosed(f"Jev monthly cap ${C.JEV_CAP} reached (log: {SPEND})")
    return today


def record_spend(today, cost, what):
    C.ROUTER_DIR.mkdir(parents=True, exist_ok=True)
    before = spent(today)
    with open(SPEND, "a") as f:
        f.write(json.dumps({"day": today, "cost": cost, "what": what}) + "\n")
    if before < C.JEV_DAY_ALERT <= before + cost:
        C.say(f"[brain-loop] Jev spend passed ${C.JEV_DAY_ALERT} today ({today}); monthly cap ${C.JEV_CAP}, log {SPEND}")


def key():
    try:
        for line in C.KEY_FILE.read_text().splitlines():
            if line.startswith("OPENROUTER_API_KEY="):
                return line.split("=", 1)[1].strip().strip("'\"")
    except OSError:
        pass
    raise GateClosed(f"no OPENROUTER_API_KEY in {C.KEY_FILE} (LK_CHECK_KEY_FILE)")


def body(state, questions):
    return {"model": C.JEV_MODEL, "state": state, "questions": questions}


def decide(state, questions, what):
    """One gated Jev call -> its answers dict ({question: {noul|score|choice, confidence}})."""
    today = spend_check()
    req = urllib.request.Request(C.JEV_URL, data=json.dumps(body(state, questions)).encode(),
                                 headers={"Authorization": f"Bearer {key()}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        d = json.loads(resp.read().decode())
    record_spend(today, float((d.get("usage") or {}).get("cost") or EST_COST), what)
    return d.get("answers") or d.get("decisions") or d, d.get("usage")
