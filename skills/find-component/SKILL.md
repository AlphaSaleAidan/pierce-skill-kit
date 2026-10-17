---
name: find-component
description: Find a ready-made UI component, animation, icon, 3D model, illustration, font, photo, video or sound that matches a plain description ("a glowing pricing card", "a marquee of client logos", "a whoosh sound"), from a vetted list of sources, then adapt it to the project. Use before building any UI element or asset from scratch, when a brief names an element, or when another skill (website-build, deck, studio-vfx) needs a part.
---

# Find a component or asset by description

The list of places to look is `sources.md` (next to this file). Search there before building anything from scratch.

## Steps
1. **Write the description as search words.** What it is + how it moves + where it sits:
   "logo marquee, infinite scroll, footer". Also note the project's stack (React/Tailwind? plain HTML?) and
   whether it needs to be free for commercial use.
2. **Pick 2-3 sources** from the matching section of `sources.md`. Prefer the ones marked for your stack.
3. **Search each one** with its search link or the site's own search. If the site blocks automated fetching,
   search the web for `site:<domain> <your words>` instead.
4. **Shortlist 3** that match. For each: link, licence, stack, and one line on why it fits. Take a screenshot
   of the demo when a human will choose.
   Many candidates? Rank them cheaply with Jev (about $0.00002 each; needs an OpenRouter key, see the script):
   `scripts/jev-rank.sh "<what you need>" candidates.tsv` (one `name<TAB>link<TAB>blurb` per line) prints a
   0-3 fit score per item, best first. It only reads the blurbs: still open the top ones yourself.
5. **Check the licence** before copying any code or file. MIT/CC0 are fine; "free for personal use", "CC BY-NC"
   or no licence at all are not fine for client or paid work. Credit the author when the licence asks.
6. **Adapt, don't paste.** Copy the mechanics, then re-skin with the project's own colours, fonts and spacing
   (from its config/tokens). Remove the library's demo colours and gradients; nothing should look like the demo.
7. **Verify** in the real page: screenshot it, check it on a phone-width screen, check reduced motion.
8. **Note the source** in the code (one comment: link + licence) so the next person can trace it.

## If nothing fits
Say so, name the closest match and what's missing, and build it yourself using the closest one as reference.
Never pass off a guess as a found item: every item you name must have a link you opened.
