---
name: phone-qa
description: Grade and improve a Vapi phone agent against a written quality bar (PHONE-BAR.md) — programmatic call grader, simulated test callers, a rubric judge subagent and a capped fix loop. Use for "grade the phone agent", "make the agent less robotic", "test the phone line", after building any demo or client voice agent, or when someone says the agent sounds off or laggy.
---

# Phone QA loop (lead fixes · a separate judge scores)

Files here: `PHONE-BAR.md` (the bar), `scripts/grade.py` (free, reads calls), `scripts/test-calls.py`
(metered, places simulated calls), `personas.example.json`. Needs `VAPI_API_KEY` in the environment
(never print it). Keep per-agent state in a folder of your own: `agents/<slug>/vapi.json`
(`{"assistantId": "...", "number": "+1..."}`), `personas.json`, and the agent's build script/config.

| Step | Run | Cost |
|---|---|---|
| 0 research refresh (optional) | if your bar's research notes are > ~60 days old, have a research subagent check current voice-agent guidance (latency, turn-taking, prompt structure) and fold changes into `PHONE-BAR.md` | free (web) |
| 1 grade real calls | `grade.py agents/<slug>/vapi.json --last 10` → `runs/<slug>-<ts>/calls.md` + `auto.json` | free (Vapi GETs) |
| 2 test calls | `test-calls.py agents/<slug>/vapi.json --personas agents/<slug>/personas.json` (dry run prints $) → **ask the human with the dollar figure** → `--yes` | vendor minutes, roughly ~$0.25/call on both legs |
| 3 grade tests | `grade.py agents/<slug>/vapi.json --since <ts printed by step 2>` | free |
| 4 judge | spawn ONE fresh subagent (it did not build the agent): "You are a demanding client who has heard the best human receptionists. Read PHONE-BAR.md (incl. its scoring calibration — start each dimension at 7 and earn points with quoted evidence) and runs/…/calls.md. Score every call D1–D10 0–10 with a quoted line per score; list which auto defects are real; name the single most robotic moment per call; give the top 3 fixes as exact prompt text or config key/value. Never round up. Write runs/…/scorecard.md." | model usage only |
| 5 fix | edit the agent's prompt/config (back it up first), redeploy, then GET the assistant and confirm `updatedAt` moved; note the change with date + evidence | free |
| 6 re-test | only the personas that failed (`--only a,b`) — same dollar ask | metered |
| 7 log | append one line to a `LOG.md`; any new failure pattern → PHONE-BAR "Lessons" + a regex in `grade.py` `ROBOTIC` if it's matchable | free |

**Pass bar:** zero real auto defects (AI-to-AI test calls get +0.5 s latency slack — the AI caller's
transcriber is slower than a human handset — no more) AND every rubric dimension ≥ 9 and overall ≥ 9.0
on EVERY persona.

**Caps (grading loops can burn a week of usage):** max 2 fix rounds per session, then deliver with the
remaining issues listed. Never re-arm a loop on silence; never poll.

**Never:** let a test call reach the hand-off (personas hang up at `hangup_when`, so no real business
rings); place test calls without a fresh dollar OK; judge wording from Vapi's bot-message text alone
when wording matters — it's a lossy phone transcription, listen to the recording (`auto.json` → `recording`).

**Verify by the effect:** a fix is done when the re-test transcript shows the behaviour changed, not when
the prompt says it should.
