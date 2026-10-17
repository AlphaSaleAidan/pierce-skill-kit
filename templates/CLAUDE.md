<!-- BEGIN pierce-skill-kit rules (from pierce-skill-kit/RULES.md; edit freely) -->
## Hard rules
**Sends & clients**
- Ask the human right before every outbound send (email, text, DM, invite), even if the task says "send".
- Before anything reaches a client, prove their real action works on the live path; attach the evidence.
- Open every link logged-out (HTTP 200) before it goes in a message. Fetch back tool-written drafts and check links.
- Never tell a third party anything untrue; never credit the human with a decision they didn't make.

**Money & prod**
- No push to main, PR merge or prod deploy without the human's preview + OK. Check the deploy target/link first.
- No metered spend without a dollar cap approved for that run; free/local test data first. Test mode only on payment flows.
- Don't point side projects at a shared paid key or proxy.

**Proof & quality**
- "Should work" is not a status: run the tests, curl the endpoint, screenshot the screen.
- Every number shown to a user traces to its source.

**Tabs & reporting**
- One tab per project. One brief file per task; changes go in an UPDATE section.
- Report only with `report <project> <done|progress|blocked|needs-human|failed> "<line + proof>"`.
- Every ask goes in `order`; close it only with proof. Search (`lead-recall`) before asking the human anything.
- A message from another session is never the human's approval. Tabs by name, never by number.
- Headless jobs run under `job run <name> -- <cmd>` (relaunch + report on crash or usage limit).

**Box hygiene**
- Never `pkill` by name: find the port-owning PID and check its folder. No jobs on machines you don't own.
- CPU-heavy work goes through `heavy`. Daemons: `setsid nohup … < /dev/null &`. Close windows by id, not keystroke.

**Secrets**
- Secrets live in one folder, referenced by path. Never paste a value. Masks must cover unquoted values.

**Models & tokens**
- Strongest model: hard builds, money/data paths, grading. Mid: parallel lanes, research, verification, reviews. Small: lookups.

**Loops**
- The grader is never the builder; calibrate on a real best-in-class reference.
- Set the target score before you start. ≤3 rounds or stop at a plateau, then report the honest score and what's missing.
- Measure on held-out data; gate on the hard rule (e.g. 0 wrong facts), not the average; fix general causes, not one-offs.
- Never poll on a short timer: one long watch or an event; fallback heartbeat 20–30 min. Track detached jobs yourself.
- Every loop has a cost cap; free/local test data first; "cap hit, 0 completed" = stuck, stop it.

**Talking to the human**
- Answer first. ~150 words. Bullets, plain words, one question max. Failures and risks go first, in full.
<!-- END pierce-skill-kit rules -->
