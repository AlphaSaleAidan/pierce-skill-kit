# Report protocol: one path in

Tabs tell the lead things in exactly one way:

```sh
report <project> <done|progress|blocked|needs-human|failed> "<one line: result + proof>" [path-or-link ...]
```

It does two things, so a report can't get lost:
1. appends a row to `$LK_HOME/reports.tsv` (time, project, status, message, proof, tab name), and
2. types `[REPORT <status>] <project> (<tab>): <message> | <proof>` into the lead's window, which wakes the lead.

A lock keeps two tabs reporting at the same moment from mixing their keystrokes. If the lead window isn't
running, the row is still logged and `report` exits 1 so the tab knows.

## When to report
| Status | When | The lead does |
|---|---|---|
| `done` | a task or milestone is finished, with proof | checks the proof itself, then tells the human |
| `progress` | a job will take >45 min, or is waiting on a slot | nothing; it now knows the ETA |
| `blocked` | can't continue without something | unblocks it or decides, same turn |
| `needs-human` | a decision only the human can make | puts the question (options + recommendation) in front of them |
| `failed` | it broke | decides next step, same turn; tells the human if it matters |

## Good reports
- `report acme-app done "checkout page fixed, e2e green on preview" https://preview.example.com/checkout`
- `report acme-app needs-human "deploy to prod? preview checked, 0 errors. Recommend yes" `
- `report data-sync failed "import stopped at row 4,102: bad date format" logs/import.log`

Bad: `report acme-app done "should be working now"` (no proof, not a status).

## The watchdog
`tab-watch` (cron, every 15 min) flags a tab to the lead with `[WATCH] …` when the tab's screen hasn't
changed for two checks in a row and it hasn't reported for `LK_IDLE_MIN` minutes. It flags once per idle
stretch, skips busy tabs, and skips tabs whose last report was `needs-human` (they're waiting, not stuck).
