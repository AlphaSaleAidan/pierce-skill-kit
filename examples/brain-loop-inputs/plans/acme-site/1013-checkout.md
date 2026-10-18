# acme-site: checkout in test mode
Status: ACTIVE | Owner tab: acme-site | Opened: 2026-10-13T09:00 by the lead | Order: #1 #2

## The owner's ask (verbatim, with date)
> 2026-10-10: "get checkout working on the Acme site, test mode only, then send Dana the staging link"

## Goal (one sentence, the outcome the owner sees)
Dana can place a test order on the staging checkout and gets a confirmation email.

## Done when (real effect + the proof the lead will check)
- [ ] A test card order goes through on https://staging.example.com/checkout (screenshot path)
- [ ] The confirmation email arrives (fetched back, subject line in the report)

## Context the tab needs (paths, ids, prior decisions, links)
- Decision 2026-10-10: test mode until the owner says so.

## Research done before this order (lead, with sources)
- `brain-loop show acme-site`: phase 1 invoice overdue, Dana approves copy.

## Directions (numbered; each one checkable yes/no with the proof named)
D1. Keep the payment provider in test mode; never switch to live keys | proof: report says test mode, no live key in the diff
D2. Place one test order end to end and attach the screenshot | proof: screenshot path in a done report
D3. Ask before sending anything to Dana | proof: a needs-human report before any send

## Rows (order ids this plan owns, from `order list`: "- 3, 4 | the ask")
- 1, 2 | checkout in test mode, then the staging link to Dana

## Execution plan (numbered, smallest safe steps)
1. Build the checkout form.
2. Wire test-mode payments and the confirmation email.
3. Test order, screenshot, report.

## Rules for this task
- No send / spend / merge / prod deploy / DNS without the owner's OK recorded in this file.
- Report with `report acme-site <status> "<line> NEXT: <next>" <proof>` at every checkpoint.

## Checkpoints (lead checks each when due; times in UTC)
- [x] CP1 due 2026-10-13T12:00 | form built | reports.tsv line 3
- [ ] CP2 due 2026-10-14T18:00 | test order placed | screenshot path
- [ ] CP3 due 2099-01-01T00:00 | Done-when proven | proof path/link

## Decisions needed from the owner (date asked -> answer)
- 2026-10-14 OK to send Dana the staging link? (tab recommends yes)

## Next steps (the tab keeps this current: what it is doing now and next; never empty while ACTIVE)
- NOW: waiting on the owner's OK to send the link
- NEXT: confirmation email template

## Next after done
- Live payments, after the owner's OK.

## Compliance grade (filled at close by `brain-loop grade <this file> --write`)
-

## Progress log (one line per event: time, what, proof)
- 2026-10-13T09:00 plan written and sent
- 2026-10-13T10:20 CP1 ticked: form built (reports.tsv line 3)
