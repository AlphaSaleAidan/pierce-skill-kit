---
name: sales-appointment-prep
description: Same-day prep for a booked sales appointment with a local business — research the prospect, write a sourced plan, build a tailored demo site + pitch deck, stand up a demo phone agent, and run a test → grade → fix loop on the live URLs until they pass. Use for "prep the appointment", "we have a meeting with X today, get the site/deck/agent ready", or any rep-facing demo package for a named prospect.
---

# Sales appointment prep (research → plan → site + deck → demo phone agent → test loop)

One folder per appointment: `appointments/<slug>/` (`appointment.json`, research, plan, QA rounds, agent ids).
This skill is the order of operations; the heavy lifting lives in `website-build`, `deck` and `phone-qa`.

| Step | Do | Output |
|---|---|---|
| 1 appointment | Pull the booking from your CRM/dialer: business, contact, address, time **in the prospect's timezone**, notes from the call. Flag it if the time already passed. | `appointment.json` |
| 2 research | A research subagent, web only: what they sell, service area, reviews, current site/socials, competitors, owner names only if public. Every fact sourced; unknowns marked `UNKNOWN`, never guessed. Capture their current site (screenshots) for the before/after. | `research.md` |
| 3 plan | From research only: the pitch angle, site sections, deck outline, the phone agent's prompt (first line = its greeting), and prices **only from your current price sheet**. | `plan.md`, `agent.md` |
| 4 build | Two parallel lanes from the plan: site (`website-build`) and deck at `/pitch` (`deck`). Optionally a `/compare` page (their site vs the demo). | repo + per-lane report |
| 5 deploy | Preview deploy (e.g. Vercel). Curl every route (`/`, `/pitch`, `/compare`) for 200 before anyone sees it. Make sure the preview isn't behind a login wall. | live URLs |
| 6 phone agent | Create the demo agent from `agent.md` (e.g. Vapi) with a demo number; store ids in `agent.json`. | assistant id, number |
| 7 test loop | Programmatic checks (broken links, layout defects, 0 to pass) + an independent visual grader (target 8/10 per page/slide) → fix lane → redeploy, ≤3 rounds. Phone agent through `phone-qa`. | `qa/roundN/` |
| 8 hand-off | Look at the live site, deck and a test call yourself, then give the rep: links, the number, 3 talking points, open risks. | short report |

Steps 2–3 skip when the file already exists, so a person can write research/plan by hand when there's time.

## Quality bar
- A content swap on last week's template reads as generic. Before the build lanes run, give them full-page
  captures of the last build the human accepted and name the structural moves you want (hero treatment,
  nav, image-led sections, process, reviews, an estimate/booking flow; deck: ≤30 words a slide, big numbers).
- Imagery must be for **that** trade. Never reuse another client's photos or logo. Paid image/video
  generation only after a cost-quoted OK (`credit-discipline-for-generation`).
- Eyeball a contact sheet of each lane's output before a grader or the human sees it.
- Review the plan for unsourced claims, the phone prompt above all: lanes and agents follow it literally.

## Never automated
- Prices and discounts: from the current price sheet, confirmed by whoever owns pricing. Payment links only on request.
- Spend: no metered APIs without a dollar-quoted OK. Phone minutes bill when dialled; test calls go through `phone-qa`'s dry run.
- Sends: no email/SMS/call to the prospect or the rep without asking the human in that moment.
- The demo agent never claims to be the prospect's real business line, never takes real bookings or payments,
  and says it's a demo if asked.
- Wait on build lanes by PID, not by pattern-matching process names.

Needs: `website-build`, `deck` and `phone-qa` (this kit); Node + Playwright; a host for previews (e.g. Vercel); a voice-agent platform account (e.g. Vapi; minutes are metered); a CRM/dialer export or manual appointment details.
