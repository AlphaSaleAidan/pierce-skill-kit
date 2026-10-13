# PHONE-BAR — the quality bar for every phone agent

Keep your own research notes next to this file and refresh them every ~60 days (see the phone-qa skill).
`grade.py` enforces the automatic parts; a Sonnet judge scores the rest against this page.

## Pass bar
- **Zero real auto defects** from `grade.py`. AI-to-AI test calls get +0.5 s latency slack, no more.
- **Every rubric dimension ≥ 9**, weighted overall ≥ 9.0, on EVERY persona — one weak call fails the run.
- **Scoring calibration:** 10 = indistinguishable from the best human receptionist you've ever called. 9 = one tiny
  tell a careful listener might catch. 8 = good AI. 7 = clearly a bot but competent. Start every dimension at 7 and
  earn points up with quoted evidence; a single robotic moment caps D1 at 7; any stock acknowledgement repeated caps
  D1 at 8; any re-ask of something the caller already said caps D2 at 6.
- **Gates:** D8 ≤ 4 (invented price/time/guarantee, or claims to be human) = the call FAILS. D5 ≤ 4 caps overall at 6.

## Rubric (judge scores 0–10 per call, quote the line that earned it)
| # | Dimension | Weight | 10 looks like | 4 looks like |
|---|---|---|---|---|
| D1 | Naturalness & personality | 10 | one specific person; contractions; varied openers | IVR cadence, "Thank you for that information" |
| D2 | Active listening | 12 | echoes the caller's detail ("a tree on the back corner, that's rough") | generic "okay"; re-asks what they already said |
| D3 | One question, brief | 12 | one question, ≤ 25 words, ≤ 2 sentences | stacked asks, monologues |
| D4 | Turn-taking & latency | 10 | p50 ≤ 1.0 s, no talk-over, no dead air > 2 s | p50 > 1.5 s, "Hello?", cuts caller off |
| D5 | Qualification completeness | 14 | every required field captured, in order, readback of numbers | missing fields, no fallback |
| D6 | FAQ / objections | 8 | answers from approved lines in ≤ 2 sentences, returns to intake | deflects, loops, rambles |
| D7 | Transfer & close | 10 | waits for last answer, one warm line, transfers; human on request immediately | transfers mid-question, ignores "get me a person" |
| D8 | Accuracy, no invented promises | 14 | nothing beyond the prompt; never claims to be human | quotes a price / time / license / coverage |
| D9 | Recovery | 5 | rephrases once, then moves on; patient with partial numbers | repeats verbatim, loops 3+ |
| D10 | Caller experience & empathy | 5 | tone fits (calm for a leak, brisk for impatient) | "Great!" to a flooding caller |

## Hard numbers
| Metric | Pass | Stretch | Source |
|---|---|---|---|
| Turn latency p50 / p90 / max (real calls) | ≤ 1.0 s / ≤ 1.8 s / ≤ 3.0 s | ≤ 0.8 s p50 | Hamming p95 <1 s support band; QA practice |
| Words per agent turn | mean ≤ 20, max 30; greeting ≤ 30 | mean ≤ 15 | Vapi/Retell "1–2 sentences" |
| Questions per turn | 1 | — | Vapi, Retell |
| Fillers | ≤ 1 per turn, ≤ 15% of turns, never during a readback | — | QA practice; Vapi's 2–4/turn rejected for intake |
| Caller name | ≤ 2 uses per call, never two turns in a row | — | QA practice |
| Same opener / stock ack ("okay", "got it", "perfect"…) | each at most once per call | zero stock acks | OpenAI "vary responses" |
| Specific reactions (echo a word the caller said) | ≥ 50% of reactive turns | ≥ 75% | QA "show understanding" QA practice |
| Dead air | none > 2 s; silence check-in at 10–15 s | — | Hamming, Vapi |
| Clarifications | rephrase once; offer a person after 2 failures | — | Hamming |
| Intake call length | 90–180 s for 4–6 fields, ≤ 240 s for 8 | — | QA practice |

## Build rules (every Vapi agent)
- Prompt sections: Identity → How you sound → What to find out → Transfer → Answer rules → FAQ → Examples.
  Repeat the 1–2 most important rules (one question per turn; wait for the answer before transferring).
- Personality = specific reactions to what the caller said, not adjectives in the prompt.
- Numbers spoken as words; zip/phone read back digit by digit; city never spelled.
- `stopSpeakingPlan.numWords` 2–3 (ignore "mm-hm"); endpointing longer after numbers (≈1.4 s).
- Only promise what the business confirmed. FAQ answers live in the prompt verbatim.
- "Are you AI?" → brief honest yes, keep going. Never claim to be human. (Disclosure-up-front policy — e.g.
  California AB 2905 — is UNVERIFIED here; check with counsel for your jurisdiction before choosing one.)

## Lessons (append one line per new failure — date, symptom, fix)
- Custom (Fish) voice + Vapi default chunking split at commas → "Hi," rendered as silence, questions lost their lift. Fix: `voice.chunkPlan.punctuationBoundaries` = `. ! ?` only.
- One-word barge-ins ("My", "Um") cut the agent off → `numWords` 3.
- Greeting starting "Hi," came out "Hi, for calling…" → never open on a lone "Hi,".
- A finished config sat undeployed for days → after every build, GET the assistant and compare `updatedAt`.
- Agent asked the last question and transferred in the same turn (never heard the answer) → prompt: "NEVER call transferCall in a turn where you asked a question"; grader flags it.
- "Last one" was transcribed/spoken as "Last 1" → say "last thing".
- Blind transfer to a business that doesn't pick up drops the caller (no fallback). Warm transfer + fallbackPlan needs a Twilio line.
- Judge wording from the RECORDING when it matters — Vapi's bot-message text is a lossy phone transcription.
- A "reaction bank" of example lines got RECITED verbatim across calls and fired on the wrong keyword. Never give the model a menu of reaction lines — give the rule (echo one concrete word in 2–6 fresh words) plus a banned list.
- Agent volunteered "free estimates" — never authorized. Any "free" claim = D8 gate; grader flags it.
- Agent re-asked facts given earlier (e.g. a town given in the first sentence) → explicit "track what you know, never re-ask" rule.
- Test persona that triggers an early transfer (emergency) reached the real business. Every persona must hang up BEFORE any hand-off can fire.
