# Benchmark teardown — what the best marketing sites actually do

Measured live 2026-08-27 (Playwright, 1440×900, computed styles from the DOM —
not vibes). Re-measure when in doubt; numbers below are the evidence base for
the direction pass in SKILL.md.

## Measured DNA

| Site | Display face | H1 size/weight | Tracking | Body bg | Distinct text colors (whole page) | Button radius | Hero container |
|---|---|---|---|---|---|---|---|
| linear.app | Inter Variable | 64px / 510 | −1.4px (−2.2%) | rgb(8,9,10) near-black | **7** | 9999px pill | 1344px |
| stripe.com | Söhne var | 48px / **300 light** | −0.96px (−2%) | white | 16 (gradient IS the brand) | 4px | 1232px |
| vercel.com | Geist | 64px / 400 | **−3.84px (−6%)** | rgb(250,250,250) | **6** | 6px | 1392px |
| framer.com | GT Walsheim | 54px / 500 | −2.16px (−4%) | black | 17 | small | **721px** (half the viewport, left-aligned) |
| apple.com/airpods-pro | SF Pro Display | product title 28px; section heads ~80px/600 | ~0 | white | 13 | square | 719px text measure |
| aman.com | **Lyon Display serif** | — (imagery-led) | — | rgb(243,238,231) warm paper | **4** | **0px square** | centered wordmark, hamburger nav |

## The principles that repeat across all of them

1. **One family, weight does the hierarchy.** Linear/Vercel/Apple run the whole
   page in a single face; hierarchy is size + weight + gray-step, never a second
   family per section. Aman = the two-font exception: one display serif + one
   utility sans. Never three faces.
2. **Big type is TIGHT.** Every large headline tracks negative: −2% (Linear,
   Stripe) to −6% (Vercel) of the font size, line-height 0.95–1.1. Default
   tracking on a 60px headline is an instant amateur tell.
3. **Light headline weights read premium.** Stripe sets its H1 at weight 300;
   Vercel 400; Linear 510. Nobody uses 700–800 display headlines. Bold is for
   14px UI labels, not heroes.
4. **Color restraint is measurable.** The disciplined sites use 4–7 distinct
   text colors across the ENTIRE page (Aman: 4). Hierarchy comes from opacity
   steps of one ink, not new hues. One chromatic accent max. (Stripe's 16 is
   their literal brand gradient — you are not Stripe.)
5. **One button shape site-wide.** Linear: everything is a pill. Aman:
   everything is a hard-corner rectangle. Vercel: everything 6px. The radius is
   a brand token decided once — mixed radii read as template assembly.
6. **Narrow measures, huge margins.** Framer's hero copy occupies 721px of a
   1440 viewport; Apple holds text to ~720px; section padding runs 120px+.
   Whitespace is the luxury signal — cramming is the budget signal.
7. **The subject does the talking.** Apple: giant product photography between
   short text bands. Aman: full-bleed landscape video/stills between quiet
   serif statements. When the subject can't be photographed, the greats DRAW in
   brand style — Linear's "FIG 0.1 / 0.2 / 0.3" blueprint-labeled wireframe
   illustrations, not stock or emoji.
8. **Section rhythm alternates register.** Quiet text band → full-bleed media →
   quiet text band (Apple/Aman), or a continuous dark canvas with generous
   bento cards (Linear/Stripe). Never ten same-weight sections in a row.
9. **Specific numbers as trust, live if possible.** Stripe's hero runs a live
   "Global GDP running on Stripe: 1.70545067%" counter; Framer shows "#9 on
   OpenRouter · 754.0B tokens this week". Real, oddly-specific numbers beat
   adjectives. (For clients: real yardages, real est. year, real hours — never
   invented stats.)
10. **Copy is short and declarative.** "Take a closer look." "Agentic
    Infrastructure." No exclamation marks, no "elevate/unleash/seamless", no
    three-adjective chains.
11. **Text links are underlined words** (Aman's "Discover more"), not every
    link dressed as an arrow-pill. Reserve the filled button for the one real
    CTA per view; nav carries 5–7 items and ONE primary action.
12. **Hospitality register (for clubs/resorts/restaurants)** = Aman: warm paper
    background, display serif, 4 ink colors, square buttons, centered wordmark,
    imagery full-bleed, tiny letter-spaced uppercase labels. This is the
    aspiration axis for hospitality/leisure brands — where SaaS-dark
    (Linear/Framer) would be the wrong register entirely.

## Steal / never

- STEAL: gray-step hierarchy on one ink · −2 to −6% headline tracking · weight
  300–500 display type · one button radius everywhere · blueprint-style labeled
  illustrations (FIG 0.1) · live/specific numbers · underlined text links ·
  Aman's paper+serif+square kit for hospitality.
- NEVER: three font families · default tracking on display type · bold-800
  hero headlines · a different accent per section · mixed button radii ·
  stock-photo section fillers · adjective copy · 10+ text colors (count them —
  it's measurable).

## How to use this file

During the SKILL.md §1 direction pass, pick the register axis first —
SaaS-dark (Linear/Framer), light-technical (Vercel/Stripe), product-theater
(Apple), or hospitality-paper (Aman) — then set the five tokens the table
makes explicit: face(s), H1 size/weight/tracking, bg ink, text-color budget
(≤7), button radius. Write them down before any code. When a draft feels off,
re-measure it the same way (computed styles + distinct-color count) and compare
against this table instead of squinting.
