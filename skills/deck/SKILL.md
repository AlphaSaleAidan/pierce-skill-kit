---
name: deck
description: Build or finish a pitch/sales deck to a written quality bar — brief → build → local capture of every slide → a fresh grader subagent scores each capture against RUBRIC.md → numbered fix rounds until every slide passes → a public review link checked with curl. Use for "build the deck", "make a deck for X", "finish the deck", "grade this deck".
---

# Deck pipeline

Files here: `BRIEF-TEMPLATE.md`, `RUBRIC.md` (the bar every grader reads), `capture.mjs` (Playwright),
`verdict.py` (pass rule + fix list). Work in `decks/<slug>-deck/` (its own git repo, outside any app repo).

1. **Brief.** Copy `BRIEF-TEMPLATE.md` to `BRIEF.md` — sourced facts only; prices only if the person
   paying confirmed them. The brief is the ONLY source of facts for every later step.
2. **Build** (skip if `index.html` exists). Hand the brief + `RUBRIC.md` + the engine contract below to a
   builder (a subagent or another coding agent). Structure must be new for this client — a content-swap of
   an earlier deck is a KILL. Missing imagery → leave a marked gap and list it; no paid generation without a
   cost-quoted OK.
3. **Capture** locally (never grade a deployed preview):
   `python3 -m http.server <free-port> --bind localhost` (background, kill that PID after) then
   `node capture.mjs http://localhost:<port>/ qa/roundN` → `deck-NN.png` (1440×810) + `phone-NN.png` strips.
4. **Grade.** Spawn ONE fresh subagent that did not build the deck: "Score every PNG in qa/roundN against
   RUBRIC.md (criteria C1–C6 with weights, KILL items cap at 5). Quote what you see. Write qa/roundN/judge.json
   as `[{"id": "<file>", "judge": {"total": <0-10>, "kill": [<kill items hit>], "defects": [<concrete fixes>]}}]`."
   Then `python3 verdict.py qa/roundN/judge.json qa/roundN/fixlist.md`.
   Pass = mean ≥ 8.5, every capture ≥ 7, no KILL.
5. **Fix round.** Builder fixes EVERY item in `fixlist.md`; slides tagged REBUILD get a new composition, not
   padding tweaks. No new facts. Commit, re-capture, re-grade. Cap the loop (e.g. 4 rounds), then report what's left.
6. **Review link.** On PASS, publish to hosting that is publicly reachable (no login wall — previews behind an
   auth wall fail for the client), `curl` it for 200 before sharing. Production promote and any send = the
   human's call, every time.
7. **Before showing anyone:** look at the last round's PNGs yourself and check every fact against `BRIEF.md`.

## Engine contract (the capture and graders depend on it)
One `index.html` (+ one CSS file, `assets/`), every slide `<section class="slide" aria-label="...">`, the current
slide has `.active`, `#N` hash = slide N, arrows/space/click advance, 1440×810 stage scaled to the viewport,
≤820 px viewport stacks every slide into one scroll. Self-host fonts. Add `X-Robots-Tag: noindex` on hosting.
