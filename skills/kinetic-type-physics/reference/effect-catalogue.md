# Reference text physics — frame-by-frame analysis + effect library spec

Source: your reference film (put it at `reference/ref.mp4`; it is not shipped), e.g. 25 fps (1 frame = 40 ms). Extract every
text window at native frame rate into `reference/fx/<window>/fNNN.jpg` with a contact sheet
`reference/fx/<window>.jpg` (yellow timecode per frame). Read those sheets, not memory. Timecodes below are examples.

Six rules still hold (letters are the unit; blur = velocity; springs with overshoot;
scale is a motion channel; overlap never cut; type behind the presenter). Below is what
each shot ACTUALLY does, frame-accurate, and the named effect it defines. Effect names are
the library API (`lib/kinetic.js` presets). "Track" = letter-spacing about the row centre.

---

## Effect catalogue (18 effects)

| # | Effect (preset) | Seen at | Mechanics |
|---|---|---|---|
| E1 | **wordZoomSettle** | 0.12–0.28 | Whole word starts ~3× scale, blurred (blur ∝ scale velocity), shrinks to rest in 4 frames (160 ms), ease-out, no overshoot visible. |
| E2 | **wordAppend** | 0.36–0.76 | Each new word flies in from the RIGHT edge (travel 120–160 ms, ease-out) with a long horizontal smear; the LINE STAYS CENTRED so the existing words shift left with proportional blur. Word gap ~120 ms. |
| E3 | **smearDissolve** | 1.16–1.24 | Whole line: blur 0→~30 px, opacity 1→0, drift +40 px right, over 3 frames (120 ms). No per-letter stagger. |
| E4 | **letterPour** | 1.00–2.08 | Letters arrive in READING order at exactly 1 letter per frame (40 ms letter stagger); each letter travels from the right frame edge to its rest x in ~160 ms with 5 % overshoot; horizontal smear ∝ velocity plus a ghost echo one frame behind. Rows staggered CENTRE-OUT (~60 ms per row from the middle row). Alternate rows are offset (brick layout, ~half a letter). |
| E5 | **letterEat** | 2.10–2.70 | Rest positions never move. Letters vanish in reading order at 1 letter per frame; each vanishing letter dissolves over 2 frames with a 60 px LEFTWARD smear and fade. Rows staggered centre-out by ~2 letters. The effect SURVIVES the cut to the next presenter/colourway (keeps running over the new plate). |
| E6 | **scatterPop** | 2.85–3.05, 33.40–33.56 | Letters appear IN PLACE in random order over ~200 ms (each letter: opacity 0→1, blur 8→0, scale 1.1→1 in 80 ms). |
| E7 | **trackCollapse** | 3.94–4.40, 2.85–3.17, 33.40–33.56 | Row letter-spacing collapses about the row centre: x = cx + (rest_x − cx)·spread(t), spread eases out with ~3 % undershoot; blur per letter ∝ its own velocity so outer letters smear most, centre letters stay sharp. a long word takes 450 ms; the short forms 160 ms. |
| E8 | **stackBloom** | 3.05–3.17 | The single row multiplies: copies spring OUTWARD vertically from the centre row (±1 rows at 3.05, ±2 at 3.09), vertical smear, 160 ms, while the type grows ~10 % and tracking tightens. |
| E9 | **giantRowSettle** | 3.30–3.58 | Three rows start at ~3× scale and ±400 px horizontal offset (alternating direction per row), settle to rest over 240 ms ease-out; heavy horizontal smear + echoes; rows staggered 80 ms top→bottom. Because scale is about the row centre the letters visibly converge. The previous stack (a mid-length word) is still fading under it (overlap 200 ms). |
| E10 | **rowLiftOff** | 3.74–3.94 | Rows exit UPWARD one at a time, top first, 100 ms row stagger, each 120 ms with vertical smear + fade; the second row wobbles/ghosts as it goes. |
| E11 | **letterEatFast** | 4.56–4.72 | E5 at 2 letters per frame (20 ms stagger), whole word gone in 200 ms; last letters hold sharp until their turn. |
| E12 | **rowSlideAlt** | 4.72–5.08 | Rows slide in from alternating SIDES (rows 1–3 from the left, 4–5 from the right), 80 ms row stagger, 200 ms travel with spring overshoot; rows land ±24 px off their aligned x, then a second 100 ms spring aligns them. Echo doubles visible (a doubled letter mid-slide). Then **breathe**: the whole block scales 1→1.15 over the 500 ms hold. |
| E13 | **defocusWhip** | 5.62–5.78, 37.60–37.72 | Full-frame gaussian blur ramps 0→40 px over 3 frames, hard cut, ramps back 40→0 over 3 frames. Room and type blur together (camera, not type). |
| E14 | **pillPop** | 10.08–10.20, 40.00–40.12 | Pill in place: opacity 0→1, scale 1.15→1, horizontal blur 20→0 px over 120 ms. Sub-pill drops out from BEHIND the pill (y −24→0, opacity 0→1) starting 120 ms later, 160 ms. Exit = plain 400 ms fade. |
| E15 | **wordMaterialize** | 36.58–36.70 | Whole word: opacity 0→1, blur 12→0, scale 1.05→1 over 160 ms, then **breathe** +4 % scale across the 850 ms hold. |
| E16 | **giantFlyThrough → stackMultiply** | 37.72–38.48 | (a) ONE giant glyph (~5×, blur 30 px) crosses right→left while shrinking to ~2.5× over 280 ms. (b) It multiplies into 3 rows and the remaining glyphs pour in from the right with tracking collapsing 2×→1 over 280 ms. (c) Rows settle scale 1.15→1 with ghost echoes over 200 ms. Total 760 ms. |
| E17 | **peelCountdown** | 38.68–39.24 | Rows 1 and 3 peel UP / DOWN with vertical smear + fade (120 ms). The middle row scales up 1→1.6 about its LEFT edge while its glyphs vanish from the RIGHT one every ~100 ms, remaining glyphs left-anchored ("4321"→"432"→"43"→"4"); the last glyph dissolves. |
| E18 | **gridCascade** | 39.40–39.84 | 4-column × 5-row grid of upright letters; every letter travels in from the right edge (~600 px in 200 ms, 5 % overshoot); COLUMN stagger 50 ms with the LEFT column first, ROW stagger centre-out 50 ms; horizontal smear + echo. Hard cut out. |

Timing constants that recur: letter stagger 40 ms (one per frame), row stagger 60–80 ms,
travel 160–240 ms, overshoot 3–5 %, holds 200–850 ms, exits 120–200 ms, overlap 150–200 ms.
