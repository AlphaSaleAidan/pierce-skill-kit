#!/usr/bin/env python3
"""Simulated callers for a Vapi phone agent: one AI caller per persona dials the agent's line from your
tester number, plays the persona, and hangs up at the hand-off point so no real business ever rings.

usage: test-calls.py <path/to/vapi.json> --personas personas.json [--from-number-id ID] [--only a,b] [--yes]
  vapi.json  = {"assistantId": "...", "number": "+1..."}   (the agent under test)
  personas   = {"hangup_when": "...", "personas": [{"name", "brief", "voice"?}...]}  (see personas.example.json)
env: VAPI_API_KEY (required); VAPI_TESTER_NUMBER_ID = Vapi phone-number id of the line that places test calls
METERED: every call bills vendor minutes on BOTH legs (roughly ~$0.25/call). Without --yes this only prints
the estimate and exits — get the human's OK on the dollar figure first.
Prints the call ids; then run: grade.py <vapi.json> --since <ts>  (calls take ~2 min to end)."""
import json, os, sys, time, argparse, importlib.util as u
from pathlib import Path

spec = u.spec_from_file_location("grade", Path(__file__).with_name("grade.py"))
g = u.module_from_spec(spec); spec.loader.exec_module(g)
api = g.api

EST_PER_CALL, WORST_PER_CALL = 0.25, 0.30   # approximate vendor cost; re-measure on your account
MAX_SECONDS = 180


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config"); ap.add_argument("--personas", required=True)
    ap.add_argument("--from-number-id", default=os.environ.get("VAPI_TESTER_NUMBER_ID"))
    ap.add_argument("--only"); ap.add_argument("--yes", action="store_true")
    a = ap.parse_args()
    vapi = json.loads(Path(a.config).read_text())
    cfg = json.loads(Path(a.personas).read_text())
    ps = [x for x in cfg["personas"] if not a.only or x["name"] in a.only.split(",")]
    print(f"{len(ps)} test calls to {vapi['number']} · est ${len(ps) * EST_PER_CALL:.2f}, "
          f"worst ${len(ps) * WORST_PER_CALL:.2f} (cap {MAX_SECONDS}s each)")
    if not a.yes:
        print("dry run — re-run with --yes once the dollar figure is approved"); return
    if not a.from_number_id:
        sys.exit("need --from-number-id or VAPI_TESTER_NUMBER_ID (a Vapi number you own for test calls)")
    ids, since = [], time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())
    for x in ps:
        sysmsg = (f"You are a caller phoning a business. {x['brief']}\n"
                  "Talk like a real person on the phone: short, casual, one thing at a time; only answer what is asked. "
                  f"HANG-UP RULE: the moment the agent {cfg['hangup_when']}, say \"Oh shoot, someone's at the door, "
                  "I'll call you back\" and immediately call endCall. Never answer that question.")
        c = api("POST", "/call", {"phoneNumberId": a.from_number_id, "customer": {"number": vapi["number"]},
                                  "name": f"qa:{Path(a.config).parent.name}:{x['name']}",
                                  "assistant": {"firstMessageMode": "assistant-waits-for-user",
                                                "model": {"provider": "openai", "model": "gpt-4.1",
                                                          "messages": [{"role": "system", "content": sysmsg}]},
                                                "voice": {"provider": "11labs", "voiceId": x.get("voice", "burt")},
                                                "endCallFunctionEnabled": True, "maxDurationSeconds": MAX_SECONDS}})
        ids.append(c["id"]); print(x["name"], c["id"])
        # one call at a time (parallel dials hit busy and skew latency): poll this call until it ends (free GETs)
        for _ in range(MAX_SECONDS // 5 + 12):
            time.sleep(5)
            if api("GET", f"/call/{c['id']}").get("status") == "ended": break
        time.sleep(10)
    # the AGENT-side call ids are what grade.py needs; they live on the agent's assistant, matched by time
    print("tester call ids:", ",".join(ids))
    time.sleep(20)  # let Vapi finish the agent-side analysis (structured data)
    print(f"then: grade.py {a.config} --since {since}")


if __name__ == "__main__":
    main()
