# Rules sheet

The rules that make one lead + many Claude tabs safe to leave running. Each rule exists because skipping it
was expensive; the *why* is the failure it prevents. Paste-ready version: [templates/CLAUDE.md](templates/CLAUDE.md).

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
