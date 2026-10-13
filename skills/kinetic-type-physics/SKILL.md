---
name: kinetic-type-physics
description: Reproduce broadcast-grade kinetic typography (word walls, giant zoom-settles, tracking collapses, letter pours/eats, grid cascades, lower-third pops) with per-letter physics that matches a reference video frame-for-frame. Use when a reference video has text "flying around" and yours looks basic. Ships the analysis recipe, a named effect catalogue (E1–E18), the deterministic glyph engine kinetic.js, and the verification loop.
---

# Kinetic type physics — analyse, name, implement, verify

Proven matching a reference brand film shot for shot. The lesson that made the
difference: **letters are the unit, blur is velocity, and every effect has
a frame-exact cadence you can read off a contact sheet.** Don't guess motion; measure it.

## 1. Analyse the reference at native frame rate (before any code)
```
python3 tools/fx_sheets.py <ref.mp4> reference/fx 02-wall-in:1.0:2.2 05-rows:3.3:4.0 ...
```
One window per text moment (in, hold, out). Read EVERY sheet with the Read tool and,
per window, write down: unit of motion (letter / word / row / block), order (reading,
random, centre-out, alternating rows), per-letter cadence (frames between letters), travel
direction + distance, duration to rest, overshoot, what blurs and along which axis, ghost
echoes, what persists across the cut, hold length, exit mechanics. 25 fps = 40 ms/frame.
Write it as `TEXT-PHYSICS.md` in the project: catalogue table + shot→effect map + engine
deltas. `reference/effect-catalogue.md` here is the worked example (18 effects).

## 2. Name the effects (library API = market-ish names)
wordZoomSettle · wordAppend · smearDissolve · letterPour · letterEat(+Fast) ·
scatterPop · trackCollapse · stackBloom · giantRowSettle · rowLiftOff · rowSlideAlt
(+realign, breathe) · defocusWhip · pillPop · wordMaterialize · giantFlyThrough →
stackMultiply · peelCountdown · gridCascade. Timings that recur: letter stagger 40 ms
(one per frame), row stagger 60–80 ms, travel 160–240 ms, overshoot 3–5 %, holds
200–850 ms, exits 120–200 ms, overlap 150–200 ms. Anything slower than that reads "basic".

## 3. Implement with `lib/kinetic.js` (deterministic in t)
- `Kinetic.text(el, string, {size, rows, width, tracking, top, leading, layout, color,
  rowOffset})` splits into per-glyph spans with rest positions + 2 echo clones.
- `Kinetic.play(group, [moves])` — each move `{at, dur, stagger:{letter, row, order,
  rowOrder}, window, from, to, spring|ease, blur, anchor}`; `from/to` may be functions of
  the glyph `g` (`g.row, g.col, g.x, g.width, g.count`). Channels: x y scale rotate
  opacity **spread** (tracking about the row centre).
- `Kinetic.update(t)` paints every glyph: closed-form damped spring → position, velocity
  → SVG feGaussianBlur level along the motion axis + 2 ghost echoes at −v·dt.
- `group.post = t => ({scale, blur, x, y})` for block-level breathe / defocus.
- Presets in `Kinetic.presets` (see catalogue). Overlap incoming/outgoing by default.
Rules baked in: type BEHIND the presenter layer; presenter never blurs; hard cut only
when the reference hard-cuts; effects may survive a cut (letterEat over a colourway swap).
Copy `lib/kinetic.js` into the project and `<script src="kinetic.js">` before the
cut's script. Wire shots with `typeShot(n, layerId, copy, layoutOpts, [P.preset(...)],
start, end)` (your own helper: one text layer per shot, presets scheduled from the shot's start).

## 4. Verify frame-for-frame (never eyeball at 0.5 s)
```
node tools/render_cut.mjs 'cut.html?timing=ref' renders/win 25 <dur> <start>
python3 tools/pair_strip.py reference/fx/<win> <ref_start> renders/win <start> 25 out.jpg
```
Read the strip. Judge cadence (does letter N land on the same frame?), smear axis and
length, overshoot, hold, exit. Common misses: a zoom that finishes in 0.10 s never reads
at 25–30 fps (min 0.25 s); giant glyphs at 5× must be hollow/outlined or the frame whites
out; a scale about the wrong origin turns "converge" into "slide"; a filter pool that
caps at 48 px stdDeviation is fine, longer smears need echoes not more blur.

## 5. Deliver
Silent side-by-side (reference left, ours right) via ffmpeg hstack, same fps and
duration, plus the per-window strips. A builder agent (e.g. Codex) can build the
engine/rewire from the spec; the lead session writes the spec and does every capture +
judgement itself. Watch background jobs by PID, never `pgrep -f`.

Engine self-check: `node tools/test_kinetic.mjs` (no browser). `render_cut.mjs` needs
`puppeteer` (or `puppeteer-core` + `CHROME_PATH`).
