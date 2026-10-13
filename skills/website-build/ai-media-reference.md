# AI media production for client sites — proven pipelines, prompts, and QA

Hard-won on a real site build (2026; the examples use a golf course, purely as an illustration). Every recipe here shipped or failed in
production. Follow the pipelines and the QA protocol EXACTLY — the failures below
all came from trusting a model one step further than it deserved.

## The three iron rules

1. **Ground every generation in real data.** Never let a video model invent a real
   place from a text prompt or a flat satellite tile. Start from a real capture
   (Google Earth 3D oblique, client photo, client PDF, client logo file).
2. **Best-of-N for anything choreographed.** One generation of a multi-beat shot
   (swing → strike → liftoff) will fail ~75% of the time in some subtle way.
   Generate 3–4 candidates in one batch, review ALL densely, ship the best.
3. **Dense-frame QA before calling anything done.** 6 sampled stills will hide a
   floating club, a missing strike, and a mid-shot dissolve (this happened).
   Minimum bar: `fps=2` frame strip of the ENTIRE clip, tiled, viewed at full
   attention, checked beat-by-beat against the brief. For choreography also check
   the 0.5 s around each beat boundary.

```bash
# dense QA strip (the non-negotiable step)
ffmpeg -y -i clip.mp4 -vf "fps=2,scale=280:-1,drawtext=text='%{pts\:hms}':x=6:y=6:fontsize=18:fontcolor=yellow:box=1:boxcolor=black@0.5" f%02d.jpg
ffmpeg -y $(for i in $(seq -w 1 16); do echo -n "-i f$i.jpg "; done) -filter_complex "concat=n=16:v=1:a=0,tile=4x4" dense.jpg
```

## Pipeline A — accurate aerial flythroughs of a REAL property (the grounded pipeline)

Real GE capture → layout-locked photoreal restyle → slow-glide i2v. Each stage
fixes the previous stage's failure mode. Never skip the restyle: direct
GE-screenshot → video works only ~80% of the time and the failures (clip stays
map-textured forever) are unfixable by prompt or model swap — two holes resisted
Veo 3.1 AND Veo 3 until the restyle stage was inserted.

1. **Capture** (headless Chromium via Playwright):
   `https://earth.google.com/web/@{lat},{lon},320a,{dist}d,35y,{heading}h,66t,0r`,
   viewport 1920×1330, ~55 s tile wait, **fresh browser per shot** (a reused
   browser returns the globe after ~4 navigations), globe-detection retry
   (dark-pixel count). Crop y 110–1190. Patch UI remnants generously —
   (0,0,400,180) blur-fill from below; a small patch leaves ghost "Dismiss" text
   that the video model bakes into a hallucinated sign.
2. **Restyle** — GPT Image 2 image-to-image, `resolution: 2k, quality: high`:
   > "Convert this 3D map render into a fully photorealistic aerial photograph of
   > the exact same golf hole. Keep the exact same layout: every fairway shape,
   > tree position, bunker, pond, cart path, green and building must stay exactly
   > where it is in the source image. …golden late-afternoon light… No text."
   GPT Image 2 preserves layout almost perfectly (verified side-by-side). This is
   what makes the output "accurate to the map".
3. **Animate** — Veo 3 i2v (`veo-3-fast` fine here), start_image = restyle:
   > "The camera glides forward very slowly and smoothly over this golf hole …
   > Keep the footage fully photorealistic exactly as it starts and keep the
   > layout exactly as shown … no speed ramps, no cuts, no rotation … camera
   > completely invisible … No readable text anywhere."
   Slow single-direction motion drifts least. Result: photoreal from frame 0, no
   head-trim needed.
4. **QA** — frame strip per clip at t≈5 s vs the source capture: same fairway
   direction? water/bunkers/buildings present and placed right? Reject and re-roll
   mismatches.

### Prompt physics that matter (video)
- Winning phrasing describes the input as **already real**: "The footage is
  already fully photorealistic from the very first frame: crisp real grass with
  visible mowing stripes…". The phrase **"preserve this exact layout" ON A MAP
  RENDER makes Veo refuse to transform it** (it preserves the map texture). Use
  "preserve/keep the layout" only once the input is already photoreal.
- Always append: "No readable text anywhere in the scene - no signage, no
  lettering on any building, no logos, no graphics, no UI." Without it Veo wrote
  a garbled sign on a hallucinated building.
- Transform-to-photoreal clips spend 1.5–2.2 s morphing — find the completion
  frame and trim the head (`-ss`). Restyle-first clips need no trim.

## Pipeline B — choreographed hero shots (multi-beat, one continuous take)

For "ball → club swings in from behind → strike → camera lifts off → holds on
scenic overview" style briefs:

- Generate the **start frame as a still first** (GPT Image 2 t2i), then i2v from
  it. Composition control + the video model anchors to it.
- Structure the prompt in **numbered beats** ("Beat 1: … Beat 2: …") and open
  with "One single continuous unbroken camera take, no cuts, no dissolves, no
  scene changes."
- **Include a body.** "Only the club, no golfer" produces a club floating down
  from the sky. "We see only his legs, shoes and the driver" produced a real
  swing. Disembodied objects break physics; partial bodies keep it.
- Demand visible cause and effect: "strikes the ball with clear visible contact",
  "the ball rockets forward and UP", "the camera rises **in the same unbroken
  take**", "eases to a stop and **holds** for the final two seconds".
- Use the **quality variant** (`veo-3-preview`) for hero shots; `veo-3-fast` for
  bulk coverage clips.
- Batch 4 candidates (2 per prompt variant), dense-QA each, ship the best.
  Candidate spread on that job: 1 good, 1 usable, 2 broken.

## Pipeline C — real client assets (never fake these)

- **Logo**: pull from the client's live site (`wp-content/uploads/...` etc.).
  NEVER AI-generate or redraw a real logo — overlay the real file in HTML/DOM,
  white-to-alpha via PIL if needed, on a light chip if it needs contrast on
  footage. DOM overlay also = "logo stays the same size while camera moves" free.
- **Menus / prices / facts**: fetch the client's published PDF/pages, transcribe
  verbatim (names, descriptions, prices), host the PDF on the site, link it.
  Never invent an item, price, hour, or stat. Unknown → omit (par unknown → no
  par row).
- **Off-season reality**: GE imagery may show a drained pool / bare trees. The
  restyle or video prompt may explicitly render it in-season ("the pool is open
  for the summer and filled with crystal-clear water") — presenting a real place
  at its best is fine; inventing amenities is not.

## Higgsfield MCP ops (learned the hard way)

- `models_explore(action:'recommend')` recommends images for video tasks —
  use `action:'search', query:'image-to-video'` instead.
- Veo3 on Higgsfield is **i2v only** (`start_image` required); t2v attempts 422.
- The first submit gets hijacked by a preset recommendation — resubmit with
  `declined_preset_id` from the error.
- Media inputs: `medias: [{type:'image', value:'<media_id>', role:'start_image'}]`
  (`value`, not `media_id`). Batch calls: `requests[{index, params:{model, …}}]`,
  max **12 per call**, plan cap **8 concurrent jobs** — run waves of 8.
- Getting local files in: `media_upload` returns ~6 KB presigned blobs per file
  (context killer). Prefer `media_import_url` — stage files in the site's `dist/`
  and serve them from a public preview URL (your own hosting or tunnel).
- Gemini-key Veo lane (`veo-3.1-fast-generate-preview:predictLongRunning`):
  ~$1.20/8s 1080p, groups of 4, state-file resume. Prepaid credits deplete
  mid-batch with 429 — the op may still contain a result URI; re-fetch the
  operation before calling it failed. Check `balance` before every batch.

## Encoding for the web (ffmpeg)

- Coverage clips: `-vf scale=1280:-2 -c:v libx264 -preset veryfast -crf 25
  -movflags +faststart -an` (~5–7 MB per 8 s — 18 clips went 754 MB → 122 MB).
- Hero: 1080p `-preset slow -crf 22 -an` (~4 MB/8 s).
- Scroll-scrubbed video: **all-intra** (`-g 1`) or seeking stutters; keep a
  standard-GOP 540p mobile variant and swap by `matchMedia`.
- Posters: grab real frames (`-ss N -frames:v 1 -q:v 3`); a video that must hold
  its final frame simply doesn't loop (`onEnded` → leave it).
- Originals live OUTSIDE `public/` (e.g. `media-src/`, gitignored) or every build
  copies gigabytes into `dist/`.

## Site-integration patterns that worked

- **One-shot hero**: video plays once, holds last frame; `onTimeUpdate` fires the
  logo at the strike timestamp; `onEnded` brings the copy; 10 s `setTimeout`
  safety net + `onError` fallback; mobile gets a loop, `prefers-reduced-motion`
  gets a poster.
- **SVG over stretched maps**: with `preserveAspectRatio="none"`, SVG `<text>` is
  distorted and `vector-effect: non-scaling-stroke` puts dash patterns in
  **screen px** (measure lengths against the rendered box, not viewBox units).
  Render labels as absolutely-positioned HTML chips instead.
- **Interactive map showpiece**: route draw-on (stroke-dash, once per visit),
  hover tracer dot along the polyline (GSAP tween over manual point-at-length),
  click → dive-zoom (transform-origin at the feature's midpoint %) into a
  full-width video stage. All gated behind reduced-motion.
