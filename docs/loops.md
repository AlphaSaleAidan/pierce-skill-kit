# Loops

Two kinds of loop run in this setup. Both go wrong the same way: they keep spending after they've
stopped helping. Each rule is one line plus why.

## 1. Grading / fix loops
Build → grade → fix → grade again, until it hits the bar.

- **The grader is never the builder.** Use a separate session or subagent with a fresh context. *Why: graders scoring their own work ran ~3 points generous.*
- **Calibrate on a real best-in-class reference.** Show the grader the best real example in the category and what score it gets. *Why: without an anchor, "looks fine" scores 8.*
- **Set the target up front** (e.g. 8/10, or "0 wrong facts"). *Why: a target picked after the fact always matches what you got.*
- **Cap rounds (≤3), then report the honest score and park** with exactly what's needed to reach the target. *Why: without a cap a loop keeps spending long after the gains stop.*
- **Measure on held-out data.** Keep examples the fixes never saw. *Why: a model tuned to 0.17 error on its tuning set scored 1.24 on data it hadn't seen.*
- **Gate releases on the hard rule, not the average.** *Why: a high average can hide the one wrong fact that matters.*
- **Each round fixes a general cause, not a one-off.** *Why: one-off patches overfit the test set and break elsewhere.*
- **Stop when it stops improving.** Two rounds flat = done; report it. *Why: round 4 rarely beats round 3.*

## 2. Monitoring / wait loops
Waiting on a build, a render, a deploy, a tab.

- **Never poll on a short timer.** *Why: each wake-up re-reads the context; short polls cost more tokens than the work.*
- **Wait on one long watch or an event:** an until-loop that exits when the condition is true, or a background task that notifies on exit. *Why: you wake up once, when there's something to see.*
- **No idle status pings.** "Still waiting" is not a report. *Why: it trains the reader to skip your messages.*
- **The lead's monitor round is the one standing loop:** `/loop lead round`, self-paced, 20–30 min apart. Each
  round starts with `lead-round` (one screen: machine, orders, tabs, jobs, heartbeats, tunnels, sweep).
- **Fallback heartbeat: 20–30 min.** Only as a safety net in case the event never comes. *Why: long enough to be cheap, short enough to catch a hang.*
- **Detached jobs don't notify, so track them** (PID + log path in your notes; check the log). *Why: a detached process exits silently.*
- **The watchdog flags idle tabs, but not ones waiting on the human.** `tab-watch` skips a tab whose last report was `needs-human`. *Why: nagging about a tab that's correctly waiting buries the tabs that are actually stuck.*

## 3. Spend and safety inside loops
- **Every loop has a cost cap** (dollars or credits), agreed before it starts. *Why: a test loop drained a paid voice API's credits.*
- **Free and local test data first;** paid calls only for the final proof. *Why: same incident: the loop didn't need real calls until the last run.*
- **"Cap hit, 0 completed" = a stuck loop. Stop it.** *Why: retries on a broken step spend the whole cap and produce nothing.*
- **≤2 heavy jobs at once** (`heavy` enforces it). *Why: a few parallel builds or captures stall every other tab on the box.*

## Patterns
```sh
# wait for a file, one watch, no polling chatter (cap at 30 min)
timeout 1800 sh -c 'until [ -f out/render.mp4 ]; do sleep 30; done' && report acme-app done "render finished" out/render.mp4

# a heavy job, queued box-wide
heavy npm run build
```
