---
name: studio-vfx
description: Recreate a reference video's look with your own footage — real presenter footage merged with built motion-graphics sets. Use for any "recreate this reference video with our footage" job. Covers reference breakdown → EFFECTS.md → brand DNA from the live CSS → named HTML components (a builder agent can write them) → RVM matte → photoreal plate → alpha composite → frame review → A/B of the pipeline.
---

# Studio VFX — reference → components → matte → composite → review

Every step leaves a file on disk, so the job is re-runnable and reviewable.

## 0. Layout
```
<project>/
  BRIEF.md          what the client asked, in their words + what "done" means
  EFFECTS.md        every effect in the reference, by STANDARD MARKET NAME
  reference/        the client's reference video(s)
  footage/          raw phone/camera footage + matte/ (RGBA PNGs) + presenter-alpha.webm
  tools/            rvm_local.py, encode_alpha.sh (this skill) + rvm_mobilenetv3_fp32.onnx
  lab/
    brand.json      brand DNA → compiled to CSS variables (edit a swatch → everything restyles)
    stage.css       stage scaffold (1600x900 #stage, pause button, reduced-motion)
    components/     one HTML file per named effect
    option-*.html   composed sequences
    footage/        symlink to ../footage/presenter-alpha.webm ONLY (not the PNGs)
  compare/          second-opinion pipeline outputs for A/B
```

## 1. Reference breakdown (BEFORE any code)
Extract frames every 3 s (`ffmpeg -vf fps=1/3,scale=720:-1`), view them all, and write
EFFECTS.md: one entry per effect with its industry name (Virtual Studio Set Extension,
Kinetic Typography Word Wall, Lower Third, Logo Badge Cloud, Frame Matte Pull-Back,
Punch-In/Wide camera states, Logotype Wipe, Colorway Swap …) and the *skill markers*
that separate it from a flat copy: directional motion blur on fast moves, spring
settles, fast-in/hold/fast-out phrasing, depth layering around the presenter, contact
shadows, hard punch-in cuts. Named components are what make it remakeable.
Text-heavy references → `kinetic-type-physics` for the per-letter analysis.

## 2. Brand DNA
Pull the real palette from the brand's live CSS (`curl` the homepage → its CSS bundles
→ count hex frequency + `font-family`). Write `lab/brand.json` `{vars:{...}, fonts:{...},
voice:...}`. Never invent colours; flag it if the client identity is ambiguous (several
companies share a name).

## 3. Components
A builder agent (e.g. `codex exec … < /dev/null` — the `< /dev/null` is mandatory in
background runs or it hangs on stdin) or the lead session writes them. The prompt must be
self-contained: point at EFFECTS.md, brand.json, the scaffold conventions, list the
component names, state the skill markers as hard requirements, constraints (no CDNs,
tokens only, inline SVG, reduced-motion, animate transform/opacity/filter/clip-path only),
and a `<div id=presenter>` with `<video id=presenterVideo src="footage/presenter-alpha.webm">`
that falls back to a silhouette. Relative paths are relative to the HTML file:
components use `../footage/`, sequences in lab/ use `footage/`.

## 4. Footage → matte (RVM, local CPU)
```bash
python3 tools/rvm_local.py footage/IN.MOV footage/matte --model tools/rvm_mobilenetv3_fp32.onnx \
  --start 7 --height 1080 --crop W:H:X:Y [--tonemap]
bash tools/encode_alpha.sh footage/matte footage/presenter-alpha
```
Gotchas baked into the script: phone rotation metadata (it probes a decoded frame, never
trusts container w/h); HLG/BT.2020 phone footage → `--tonemap` to Rec.709 (zscale+mobius)
or the cutout looks washed; erode ~1 px + feather 0.8 px to kill bright rims; crop to the
body so the presenter fills the `#presenter` slot. ~4 fps at 608x852 on CPU. VP9 alpha
plays in Chrome/Firefox/Edge; Safari needs HEVC-alpha (macOS encoder only) — the
silhouette fallback covers it. Verify with a check frame over the brand colour + `alphaextract`.

## 4b. Photoreal plate (the "reality" half of the merge)
Generate the set as a still with any image API (quote the cost first —
`credit-discipline-for-generation`): "empty photoreal studio, single-point perspective,
<room details>, huge seamless backdrop sweep in <brand colour>, no people, no text".
Downscale to 1920 w into `lab/plates/`. Brand-exact backdrop: build a sweep mask
(threshold the backdrop pixels → median → close holes → blur; **save as RGBA with
alpha = mask**, CSS masks read alpha) and layer `<div id=tint>` with
`background:var(--brand); mix-blend-mode:color; mask-image:url(mask.png)` (+ a 35 %
multiply copy for depth) over `<img id=plate>`. The tint follows brand.json, so a
colourway swap re-tints the real photo. Presenter: pin the cutout's bottom below the frame
(`bottom:-24px`), side-fade with a horizontal mask where limbs leave the source frame.
Punch-in origin ≈ `50% 62%` so the zoom centres on the face.

## 5. Composite + review
Presenter slot ~400x560 at bottom:104px in a 1600x900 stage for a 608x852 cutout; the
presenter's feet reach the floor line in wide shots, and the punch-in scales the same
layer (no second video). Serve `lab/` with a local static server, screenshot the sequence
at several timestamps with Playwright/Puppeteer (`waitUntil:'load'` — live-reload
connections keep `networkidle` from firing; frame-exact renders: `kinetic-type-physics`
`tools/render_cut.mjs`) and judge against the reference frames side by side. For the
client, share a public preview URL from your own hosting or tunnel, behind a passcode.

## 5b. Spend rules
Stills before video, cost preflight first, one generation per approved beat, graphics
always in HTML (free). The person paying approves every video spend explicitly.

## 6. A/B the pipeline
Give a second builder the same matte/composite task into `compare/` and read its report —
a second opinion is how the HLG tone-map issue was caught. Merge the better technique
into `tools/`.

## Rules that bit us
- Kill background jobs by PID; `pkill -f <pattern>` can match your own shell.
- No invented stats in on-screen copy; log client hours and spend the same session.
