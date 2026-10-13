# Prompting: getting agents to do what you meant

Every other part of the kit runs on prompts: briefs, rules, graders, subagents. The common thread: **say the
outcome, the bar and the limits; ask for proof; keep it on disk if it's long.**

## 1. Briefs that agents execute well
Template: [templates/brief.md](../templates/brief.md). Details: [briefs.md](briefs.md).
- **GOAL / CONTEXT / DONE-WHEN / LIMITS / REPORT**, in that order.
- **Quote the human's ask verbatim** at the top. Your paraphrase is a guess; their words are the spec.
- **One task per brief.** A follow-up goes in an `UPDATE n` section of the same brief, not a new wall of text.
- **DONE-WHEN is checkable** (a URL loads, a test passes, a count matches), so "done" can't mean "I think so".

## 2. Talking to Claude
- **Name the outcome and the bar,** not the activity. Weak: "improve the landing page". Strong: "the hero should
  read as clearly as <reference site>'s; target 8/10 from an independent grader".
- **Give the real reference:** a screenshot, a best-in-class example, the failing output. Words alone get the average.
- **Say what NOT to do:** "no new dependencies", "don't touch the payment flow", "no stock gradients".
- **Ask for proof, not claims:** "attach the screenshot / test output / curl result", not "confirm it works".
- **Set the format and length:** "answer first, 5 bullets max", "a table: file, problem, fix".

| Before | After |
|---|---|
| "Fix the signup bug." | "Signup fails for emails with a `+`. Reproduce it first, fix the root cause, add a test that fails before the fix. Report the test output." |
| "Make the report look better." | "Match the layout of the attached reference. Keep our colours from the theme file. Screenshot it at 1280px and grade it vs the reference." |
| "Research competitors." | "List the 5 strongest competitors with their price, one standout feature, and a source link each. Table only. No guesses: mark unknowns." |

## 3. CLAUDE.md and system prompts
- **Hard rules first,** then the softer preferences. The first screen is what gets followed.
- **Every rule carries its why** in one line. A rule with a reason gets applied to cases it didn't name.
- **Short and scannable:** bullets, one rule per line. See [RULES.md](../RULES.md) and [templates/CLAUDE.md](../templates/CLAUDE.md).

## 4. Creative and generation prompts (images, video, voice)
- **Showcase brief structure:** art direction (mood, references) → composition/geometry → materials and light →
  motion and interaction → checks (what must be true in the frame) → budget (credits, attempts).
- **Video: storyboard shot by shot.** One line per shot: framing, subject, action, camera move, duration.
  Get the storyboard signed off before spending a single credit.
- **Negative prompts:** list what must not appear (extra fingers, text artifacts, a brand logo, a style to avoid).
- **Reference images beat adjectives.** Attach the look you want; describe only what differs from it.
- **Quote the cost first** (see [loops.md](loops.md)): generation is metered.

## 5. Grader prompts
- **Independent judge:** a fresh session or subagent that didn't build the thing.
- **Calibrated rubric:** define what a 5, 8 and 10 look like, anchored on a real best-in-class reference shown
  side by side. Tell it graders run generous and to score strictly.
- **Output:** a score per criterion, **the one biggest fix**, and evidence (where in the screenshot/output).
  "The one biggest fix" keeps each round focused on a general cause.

```text
You are a strict, independent reviewer. You did not build this. Compare the attached screenshot with the
reference (a top site in this category). Score 1-10 on: hierarchy, typography, spacing, clarity of the main
action. An 8 means it could pass as the reference's own page. Graders tend to be ~3 points generous: correct
for it. Output: a table of scores with one line of evidence each, then THE single biggest fix.
```

## 6. Subagent prompts
- **Self-contained:** a subagent doesn't see your chat. Give the goal, the exact files/paths, the limits and done-when.
- **Name the report format:** "under 300 words: findings as `file:line, problem, fix`; 'none' if none".
- **Limits travel with it:** no sends, no deploys, no spend, no deletes, read-only if it's an audit.
- **Fan out when** the pieces are independent (audit 40 files, research 5 vendors, grade 3 pages). **Do it
  yourself when** it's the critical path or needs context you'd have to retype.
- **Verify what comes back.** Spot-check its claims before you pass them on.

## 7. Dictation
People talk fast and loose, and speech-to-text mangles names and numbers.
- **Read for intent,** not literal words: "make it pop on the phone" = the mobile view needs work.
- **Read back numbers, names and anything irreversible** before acting: "deploying acme-app to prod, price $49/mo: correct?"
- When a word makes no sense, it's usually a mis-heard name. Ask, don't guess.
