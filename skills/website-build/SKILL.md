---
name: website-build
description: Repeatable recipe for shipping a premium marketing/ecommerce site that does NOT read as AI-generated. Use for any new site, landing page, or "remake this website" job. Covers direction → assets → build (React/Vite/Tailwind/GSAP/Lenis/Framer Motion) → verify → preview link.
---

# Website build playbook

Hard-won on client sites where two "clean" drafts (dark-navy, serif-italic, glass cards) were rejected as
"AI slop" before the version that shipped. Follow this in order; skipping the direction pass is how the
slop happens.

## 0. Load first (every time)
1. `frontend-design` from [anthropics/skills](https://github.com/anthropics/skills) — the brief-to-tokens process.
2. `design-motion-principles` ([kylezantos/design-motion-principles](https://github.com/kylezantos/design-motion-principles)), build mode. E-commerce/marketing → Jakub primary, Emil secondary.
3. [awesome-claude-design](https://github.com/rohitg00/awesome-claude-design): `prompts/break-default-aesthetic.md` = the reject list; `design-md/<family>/*.md` = a DESIGN.md format to copy.
4. Your own notes on the owner's / client's taste, and the design rules in your CLAUDE.md.

## 1. Direction pass (before any code)
Read `great-sites-teardown.md` in this folder — measured DNA of Linear/Stripe/Vercel/Framer/Apple/Aman (type
sizes, tracking, colour budgets, radii) + the 12 principles. Pick the register axis (SaaS-dark /
light-technical / product-theater / hospitality-paper) and set the five tokens it names before writing code.
Write a DESIGN.md-style block, then state it in ≤8 lines:
- **Subject + single job** of the page. Pull vocabulary from the subject's own world (for a specialty
  coffee roaster: green beans, roast curves, cupping scores, origin altitude, bag valves). The signature
  element comes from here.
- **Palette**: 4–6 named hexes from the client's REAL brand (tailwind config / CSS vars / current site).
  One chromatic accent. Never cream+terracotta, never black+acid-green, never navy+glass cards, never
  purple-pink gradients.
- **Type**: characterful display face + complementary body + utility mono. Never Inter/Roboto/system as
  the chosen face; avoid wide grotesques. Fraunces (opsz 144) + IBM Plex Sans/Mono worked as a
  "scientific journal" pairing. **No italic-word-in-accent-colour headline trope** — it's the #1 AI tell.
  Use colour on a phrase, not italics.
- **Signature**: the ONE thing the page is remembered by (e.g. a pinned spec-sheet hero — product cutout
  annotated by scroll-drawn callouts). Spend boldness here; keep everything else quiet.
- **Structure is information**: numbered markers only for a real sequence. No 3-col feature grid as
  section 2. No "Get Started / Learn More" pair.
- Self-check: "would I produce this for any similar brief?" If yes, change it.

## 2. Assets (real, on-brand, no stock)
- **Product imagery**: one master render with a BLANK label on pure white (any image model at 2k/high),
  then composite every SKU label programmatically — consistent, zero AI text errors, ~30 KB webp each.
  Label compositing in a few lines of PIL: render the label art flat, warp it onto the product's curve
  (sin x-map for a cylinder + edge falloff), multiply-blend it over the blank label area, add a soft
  specular band on top:
  ```python
  from PIL import Image, ImageChops
  base = Image.open("master_blank.png").convert("RGB")
  label = Image.open("label_sku.png").convert("RGB").resize((w, h))    # pre-warped to the curve
  region = base.crop((x, y, x + w, y + h))
  base.paste(ImageChops.multiply(region, label), (x, y))                # surface shading shows through
  ```
  Never ship AI renders with blue-flame/neon backgrounds.
- **Cutout**: background removal on the master → hero PNG + webp.
- **Hero video** only if it's literally the subject and ambient (5 s, ffmpeg crossfade seam, ~200 KB).
- Fonts for compositing: `raw.githubusercontent.com/google/fonts/main/ofl/<family>/<File>[axes].ttf`.
- Check your generation balance first; credits aren't free (`credit-discipline-for-generation`). Never
  fabricate lot numbers/stats.

## 3. Stack + mechanics
`vite + react 19 + tailwind 3 + framer-motion 12 + gsap 3.13+ (+ @gsap/react) + lenis/react + zustand`.
- `src/lib/gsap.js` registers ScrollTrigger + SplitText (free since 3.13) + useGSAP. App wraps in
  `<ReactLenis root options={{autoRaf:false}}>` and forwards `lenis.on('scroll', ScrollTrigger.update)` +
  `gsap.ticker.add`. Skip Lenis on touch + reduced-motion.
- Mechanics that earned their place: pinned+scrubbed hero (`pin:true, end:'+=140%', scrub:.6`, desktop-only
  in `gsap.matchMedia`); SplitText line-mask reveal; scroll-velocity marquee; sticky-scroll reveal driven by
  `useScroll({target})` (Lenis-safe); number ticker; spotlight card (CSS vars).
- Gotchas: GSAP `xPercent` overwrites Tailwind `-translate-x-1/2` → own the transform in GSAP
  (`fromTo xPercent -50`); `-z-10` children vanish unless the section is `isolate`; `inset:-50vw` glows need
  `overflow-x: clip` on html/main; `useEffect(() => initLenis())` returning an object crashes React 19
  ("destroy is not a function"); flex-squashed SVG icons need `flex-shrink:0`; restart Vite after editing
  tailwind.config; never `ScrollTrigger.getAll().forEach(t => t.kill())` in a component cleanup — scope with
  `useGSAP`/`gsap.context`. GSAP horizontal pinned rails can be fragile — a framer `drag="x"` carousel with
  arrows is the safer fallback.
- Motion rules: springs `bounce:0`, 200–500 ms, exits subtler than enters, `prefers-reduced-motion` path in
  the same code, only transform/opacity/filter.

### Component sources (copy the mechanics, re-skin completely)
[React Bits](https://reactbits.dev) · [Aceternity UI](https://ui.aceternity.com/components) ·
[Magic UI](https://magicui.design/docs/components) · [KokonutUI](https://kokonutui.com) ·
[21st.dev](https://21st.dev/community/components) · [GSAP docs](https://gsap.com/docs/v3/) ·
[Lenis](https://github.com/darkroomengineering/lenis). Check each component's license; strip its demo
palette and re-theme to the brand before it ships. To find one that matches a description, use `find-component` (~45 sources by type).

## 4. Verify (never call it done without this)
Playwright screenshots at scroll positions (1440×900 and 390×844 for mobile), downscaled ≤1400 px before
viewing. Check: hero in one viewport, no text on top of the product, full-page width == viewport (no
overflow), hamburger icon visible, tickers settle, pinned sections release. Fix, reshoot, then commit on a
feature branch.
- **Generated VIDEO is never verified by sampled stills.** `fps=2` dense frame strip of the whole clip,
  beat-by-beat against the brief, before it ships (6 sampled frames once hid a floating object, a missing
  beat and a mid-shot dissolve; the strip caught all three). Choreographed shots: best-of-4 candidates,
  review every one.

## 5. AI media (flythroughs, hero shots, real client assets)
Read `ai-media-reference.md` in this folder BEFORE any generation work on a site: grounded flythrough
pipeline (real capture → layout-locked restyle → i2v), beat-structured hero prompts (partial bodies, never
disembodied objects), real-logo/menu handling (fetch real files, never AI-redraw), Higgsfield MCP call
shapes + rate limits, ffmpeg web-encoding ladder, and the dense-QA protocol.

## 6. Preview
`vite build` → `vite preview --host 127.0.0.1` with `preview.allowedHosts` set → share a public preview URL
from your own hosting or tunnel. Never deploy prod unpreviewed; the owner approves the promote.

## 7. The bar
Dense premium > minimal ("white-minimal" got rejected as "basic" too); diagrams over prose; interactive
explainers; honest numbers with motion; structural redesigns only; inline stroke-SVG icons only, no emoji;
real palette; verify visually.
- Dense + dramatic + real imagery is what landed: a product-commercial hero, a generated scene plate from
  the product's world, a product turntable video, generated photography for sections.
- **Product turntable recipe:** dark still from a labelled reference → image-to-video "rotates 360°,
  returns to start" (some models ignore the rotation — test) → 0.3 s xfade seam (longer = ghosted label) →
  mp4 crf23 + webm → `mix-blend-screen` over a black radial plate (if the bg-removal output has no alpha).
  Time-based loop, not scroll-scrub (mobile).
- **Labels:** keep the client's original artwork language (finish, metal, emboss) AND project it onto the
  shape — flat pastes read fake.
