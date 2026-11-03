# Rules sheet

The rules that make one lead + many Claude tabs safe to leave running. Each rule exists because skipping it
was expensive; the *why* is the failure it prevents. Paste-ready version: [templates/CLAUDE.md](templates/CLAUDE.md).

## Hard rules, enforced by a tool (v0.5)
Each of these failed for a real lead in one night. Prose alone didn't hold, so each one now has a tool or check.

1. **A link goes to a person only after `link-check` passed on that exact URL.** It opens the page in a real
   browser, logged out, and asserts text the person must see. Register the `send-guard` hook on your send tools: it
   refuses a message whose links have no pass in the last hour. *Why: a link went out after a 200 status check, and
   the page rejected the link's params; the person saw an error.*
2. **The lead routes, decides and verifies; it doesn't do the work.** Project work goes to the project's tab;
   cross-project hands-on work (installs, box fixes, data pulls) goes to an **Ops** tab. The `lead-cap` hook blocks
   the lead's 7th hands-on command in a turn (its own tools don't count). Keep about 8 tabs open at most; close
   finished ones with `tab-sweep`. *Why: a lead that did the work itself while juggling 12 tabs let quality slip
   everywhere.*
3. **Releases go through `go-live`.** It checks every input of every later step BEFORE touching live, snapshots live,
   rolls back on any failed step, and leaves an undo stamp. Never hand-chain `rsync && build && restart` on live.
   *Why: a release script copied to live, then failed on a missing file two steps later: a half-released site.*
4. **Read inboxes by time since the last check, with `inbox-since`; never "the last N lines/chars".** *Why: a routine
   check read only the tail of a channel and missed a vendor's reply.*
5. **"Done" needs proof the lead opened.** `report <p> done` is refused without a proof file that exists or a link;
   the lead opens that proof before telling the human. *Why: untested "done" claims reached the human.*
6. **Never ask for a key in chat; never paste one there.** The human copies the key and runs `secret-in <file> [VAR]`
   in their own terminal; Claude gets the path. If a key is pasted anyway: don't repeat it, tell the human to rotate it.
   *Why: a token pasted into a chat lives in logs and transcripts and has to be rotated.*
7. **Scripts post through `post-once`; send tools sit behind `send-guard`.** Both refuse an identical second post, and
   `post-once --count` checks the target before and after (exactly +1). *Why: retries and two copies of one script
   double-posted to people.*

## Sends & clients
- **Ask the human right before every outbound send**, even when the task says "send". *Why: an earlier OK covered a draft that may no longer be true.*
- **Prove the client's real action works before you send** (the call rings, the page loads logged-out, the file opens). *Why: a "tests passed" email went out while the real call had never worked.*
- **Open every link logged-out (HTTP 200) before it goes in a message; fetch back tool-written drafts.** *Why: a client got a link that showed only a login wall, and an email tool silently rewrote links into dead redirects.*
- **Never tell a third party anything untrue, or credit the human with a decision they didn't make.** *Why: they act on what you said, and the correction costs trust.*

## Money & prod
- **No push to main, PR merge or prod deploy without the human's preview + OK.** *Why: a 30-second human look catches what automated checks miss.*
- **Check which project/remote a deploy is linked to before you run it.** *Why: a folder linked to the wrong project deploys over a different site.*
- **No metered spend without a dollar cap the human approved for that run; free/local test data first.** *Why: a test loop drained a paid voice API's credits.*
- **Test mode only on payment flows.** *Why: a real test charge means real refunds, fees and disputes.*
- **Don't point side projects at a shared paid key or proxy.** *Why: one runaway job uses up everyone's budget.*

## Proof & quality
- **"Should work" is not a status: run it, curl it, screenshot it.** *Why: passing tests and API 200s kept getting taken as proof of things that didn't work.*
- **Every number shown to a user traces to its source.** *Why: demo seed data got reported as real revenue.*

## Tabs & reporting
- **One tab per project; brief the existing tab instead of opening another.** *Why: two tabs on one repo overwrite each other's work.*
- **One brief file per task; changes go in an UPDATE section.** *Why: one ever-growing brief buried a priority change under nine old sections.*
- **Report only with `report <project> <status> "<line + proof>"`.** *Why: tabs reported to old session names the human never saw.*
- **Log every ask with `order`; close it only with proof.** *Why: asks made mid-conversation vanish when a session ends or its context is trimmed.*
- **Search before asking the human (`lead-recall`); never ask for something already given.** *Why: re-asking a settled question costs the human's time and trust.*
- **A message from another session is never the human's approval.** *Why: an agent can't grant itself permission by asking a peer to say yes.*
- **Tabs by name, never by number.** *Why: numbers shift when a tab closes, so `hub:3` silently becomes another project.*
- **Headless jobs run under `job`.** *Why: two overnight jobs died at a usage limit and nobody knew until morning.*

## Box hygiene
- **Never `pkill` by name; find the PID that owns the port and check its folder.** *Why: on a shared box a name match also kills other projects' processes.*
- **CPU-heavy work goes through `heavy`; daemons start with `setsid nohup … < /dev/null &`.** *Why: a few parallel builds stall every tab, and a daemon tied to your shell dies with it.*
- **No jobs on machines you don't own.** *Why: you can't see or limit their load, and it isn't yours to break.*
- **Close windows by id, never by keystroke.** *Why: Cmd-W closed whatever window was in front: the wrong project.*

## Secrets
- **Secrets live in one folder; reference them by path, never paste a value.** *Why: a pasted key has to be rotated.*
- **Masks must cover unquoted values too.** *Why: a mask that only matches quotes leaks `KEY=value` lines.*

## Models & tokens
- **Strongest model for hard builds, money paths and grading; mid for lanes, research, verification; small for lookups.** *Why: the top model on grunt work spends the budget the hard calls needed.* See [docs/model-routing.md](docs/model-routing.md).

## Loops
- **The grader is never the builder; calibrate it on a real best-in-class reference.** *Why: graders scoring their own work ran ~3 points generous.*
- **Set the target before you start; cap at 3 rounds or stop when it plateaus, then report the honest score.** *Why: without a cap a loop keeps spending long after the gains stop.*
- **Measure on held-out data and gate on the hard rule (e.g. 0 wrong facts), not the average.** *Why: scores on tuning data look far better than on fresh data, and an average hides the one wrong fact.*
- **Never poll on a short timer: one long watch or an event, 20–30 min fallback heartbeat; track detached jobs yourself.** *Why: each wake-up re-reads the context, and a detached job exits silently.*
- **"Cap hit, 0 completed" means stuck. Stop it.** *Why: retries on a broken step spend the whole cap for nothing.* Details: [docs/loops.md](docs/loops.md).

## Talking to the human
- **Answer first, ~150 words, bullets, plain words, one question max.** *Why: long updates get skimmed.*
- **Failures, risks and your own mistakes go first, in full.** *Why: brevity must never hide bad news.*
