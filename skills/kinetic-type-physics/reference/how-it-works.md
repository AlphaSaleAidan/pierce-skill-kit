# How the kinetic text physics works (and how to reuse it)

The whole engine is one idea applied ruthlessly: **every letter is its own physics
object, and blur is never faked — it's computed from real velocity.** Engine:
`lib/kinetic.js` (~256 lines, zero dependencies).

## The four layers

**1. The spring is math, not simulation.** Each move animates a letter from A to B
using a closed-form damped-spring equation (`response()`). Because it's a formula
in `t`, not a step-by-step simulation, you can jump to any timestamp and get the
exact same frame — that's what makes deterministic rendering and `?t=12.8` seeking
possible. Damping is clamped so every landing overshoots by 3–5% — the tiny
"settle" that reads as physical.

**2. Blur = velocity.** The same equation also returns the letter's *speed* at that
instant. Speed picks one of 12 pre-built directional Gaussian filters (x or y axis,
whichever the letter moves along). Fast letter → heavy smear along its motion path;
at rest → perfectly sharp. Nothing is ever "given" a blur; it earns it by moving.
Two ghost echoes are painted 1 and 2 frames behind the letter, opacity scaled by
speed — that's the film-like trail.

**3. Letters are the unit; rows and words are just stagger.** A word wall pouring
in is one preset: every letter does the identical 160 ms spring, offset by 40 ms
each (1 letter per frame at 25 fps), rows offset centre-out. All the reference's
showpiece effects reduce to cadence choices like this — the 18-effect catalogue
(`effect-catalogue.md`) is really ~6 mechanics × different staggers.

**4. Channels compose.** A letter's state has x, y, scale, rotate, opacity, and
`spread` (letter-tracking about the row centre — the "tracking collapse" effect).
Each move only touches channels it declares, so a pop-in, a tracking collapse, and
a scale settle can run simultaneously and add cleanly.

## Reusing it in a new project

Include the engine, then:

```js
const g = Kinetic.text(el, 'SAY IT LOUD', {rows: 5, size: 110});
Kinetic.play(g, [Kinetic.presets.letterPour({at: 2.0}),
                 Kinetic.presets.letterEat({at: 3.1})]);
// in your render loop, driven by your own clock:
Kinetic.update(t);
```

Full API: `engine-api.md`. Preset factories: wordZoomSettle, wordAppend,
smearDissolve, letterPour, letterEat(+Fast), scatterPop, trackCollapse,
stackBloom, giantRowSettle, rowLiftOff, rowSlideAlt, realign, pillPop,
wordMaterialize, giantFlyThrough, stackMultiply, peelCountdown, gridCascade,
plus container helpers breathe / defocusWhip.

## The recipe matters as much as the code

When matching a new reference:

1. Extract its text windows at **native** fps first (`tools/fx_sheets.py`) —
   never eyeball at playback speed.
2. Read the contact sheets frame-by-frame; name the cadences (letter stagger,
   travel time, overshoot).
3. Only then wire presets.
4. Close the loop: `tools/render_cut.mjs` renders your version at the same 40 ms
   cadence, `tools/pair_strip.py` strips it against the reference — fix what
   differs, re-render.

## Constants worth memorizing

- Letter stagger: **40 ms** (1 per frame at 25 fps)
- Row stagger: **60–80 ms**, often centre-out
- Travel: **160–240 ms**
- Overshoot: **3–5%**
- Exits: about **half** the entry time
- Overlap between effects: **150–200 ms** — never a dead cut

Copy those numbers and almost anything looks broadcast-grade.
