# kinetic.js engine API


- `Kinetic.text(el, copy, options)` now accepts `rowOffset: row => pixels`. Glyph metadata includes `rows`, `rowLeft`, and `rowCentre`, recalculated by `Kinetic.reflow()` after font loading.
- Moves accept numeric `spread` (default 1). It adds `(glyphCentre − rowCentre) * (spread − 1)` to painted x. Its analytic velocity contributes to horizontal smear and echo displacement.
- `stagger: {letter, row, order, rowOrder}` uses milliseconds. `rowOrder` is `top` (default), `bottom`, or `center`. Centre-out rows use distance from the middle row; symmetric rows share a beat. Existing glyph orders remain supported.
- Catalogue presets set `exactStagger: true`; a legacy `window` cannot compress their cadence. Legacy presets retain their existing window behavior.
- `anchor: 'left'` on a move makes row scale pivot around its measured left edge. Default scale pivots around the row centre. The selected anchor persists for subsequent moves.
- `group.post = t => ({scale, blur, x, y})` applies a container transform and Gaussian blur on every update. Omitted values reset to identity. Reduced motion bypasses the post transform.
- `blur` is an explicit glyph blur envelope, quantized through the existing 12-level directional SVG pool. `smear` adds a pixel-length echo trail over a 40 ms interval without shifting the main glyph; `letterEat` uses this to keep the surviving text stationary.
- `Kinetic.play(group, script)` flattens nested preset arrays. Moves affect only channels they declare, allowing tracking, pop, scale and exits to compose. Each sample rebuilds state from the script; seeking does not integrate prior frames.
- Spring damping is bounded to approximately 3–5% overshoot. `ease:'out'` supplies the non-overshooting cubic travel; `ease:'linear'` supplies linear dissolve envelopes.
- The x/y SVG pools still contain 12 levels each. Two velocity-weighted echoes remain, now spaced one and two 25 fps frames behind the glyph.

New move factories: `wordZoomSettle(o)`, `wordAppend(prefixLength,o)`, `smearDissolve(o)`, `letterPour(o)`, `letterEat(o)`, `letterEatFast(o)`, `scatterPop(o)`, `trackCollapse(spread,o)`, `stackBloom(o)`, `giantRowSettle(o)`, `rowLiftOff(o)`, `rowSlideAlt(o)`, `realign(o)`, `pillPop(o)`, `wordMaterialize(o)`, `giantFlyThrough(o)`, `stackMultiply(o)`, `peelCountdown(o)`, `gridCascade(o)`.

`o` accepts normal move overrides, including `at`, `dur`, `select`, and `stagger`. `pillPop({sub:true})` supplies the role drop; callers schedule it 120 ms later. `wordAppend` returns prefix recentering and suffix travel moves. The opener uses measured prefix bounds for exact centering after reflow.

Post helpers: `breathe(at,duration=.5,amount=.15)` and `defocusWhip(cut,duration=.12,maxBlur=40)` each return a pure `t => state` function. The cut applies defocus to the whole scene container, so room, presenter, text and logo blur together while existing camera transforms remain intact.

`peelCountdown` defaults to one glyph every 100 ms, right-to-left. Optional `steps` groups a longer string into a specified number of removal beats without speeding up that cadence.

Verify renders with `tools/render_cut.mjs` + `tools/pair_strip.py` (see SKILL.md §4).
