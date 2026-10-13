---
name: codex
description: Hand a build, refactor, test sweep, or adversarial code review to an OpenAI model through the Codex CLI while Claude keeps the brief, secrets, MCP steps, verification and the report. Use for "/codex", "send this to codex", a substantial build or mechanical grind you want off Claude's usage, or a second-model review of any diff touching payments, email, deploys, DNS or auth.
---

# /codex — Claude leads and verifies, a Codex model builds

Usage: `/codex <task>` · `/codex review` (adversarial review of the current diff) · `/codex fix <failing thing>`

## 0. Pick the model (always pass `-m`)

Keep a small table of the Codex models you have access to, by job. Example shape (fill in your own
model names — they change often):

| Job | `-m` | effort |
|---|---|---|
| Money/auth/email/DNS/deploy review | `<strongest model>` | `high` |
| Look matters (site, deck, motion), image-to-code, new system | `<strongest model>` | `medium` |
| Feature in an existing pattern, numbered fix round, refactor, parallel lane | `<workhorse model>` | `medium` |
| Lint, deps, renames, test sweep, format conversion, log triage | `<cheap/fast model>` | `low` |

Unsure → workhorse. The workhorse misses the same symptom twice → strongest.
Effort flag: `-c model_reasoning_effort=<low|medium|high>`.

## 1. Write the brief (the Codex model has no memory of this session)

Write it as an md file (`<repo>/docs/handoff/<slug>.md` or your scratchpad); a one-liner for a cheap
model can be inline. Self-contained, in this shape:

```
REPO: <abs path>            BRANCH: <name>        DO NOT COMMIT.
GOAL: <one sentence — what "done" looks like>
CONTEXT: <2–5 lines: what exists, entry points, file paths, how it's run/tested>
CONSTRAINTS: <brand palette / no emoji / keep files <500 lines / don't touch X / match existing style>
DELIVER: <files to create or change> + <how to prove it works: test cmd, screenshot, curl>
REPORT: end with a ≤10-line summary: files touched, how you verified, anything unsure.
```

Never put API keys, secret-file contents, or customer data in the prompt.

## 2. Run it

```bash
codex exec -m <model> -c model_reasoning_effort=<effort> -C <repo> -s workspace-write \
  --skip-git-repo-check -o <scratchpad>/codex-last.md "$(cat <brief.md>)" < /dev/null
```

- `< /dev/null` is mandatory — without it codex hangs on "Reading additional input from stdin".
- Long runs: run in the background and read the `-o` file when it exits; don't poll in a loop.
- Needs the network (npm install, fetch a URL)? add `-c sandbox_workspace_write.network_access=true`.
- Review: use Codex's native reviewer, not a hand-rolled prompt:
  `cd <repo> && codex review -c model=<model> --uncommitted < /dev/null` (`--base main` for a branch).
  Gotchas: NO `-C` flag — cd first; `--uncommitted`/`--base` CANNOT be combined with a custom
  prompt — a prompt only works as `codex review "<instructions>"` on the whole tree.
- Shared skills: symlink the design/build skills you want Codex to use into `~/.codex/skills/` and
  name the skill in the brief ("follow the website-build skill") — it loads it itself.
- MCP servers registered for Codex that need approval (paid generation etc.) are auto-denied under
  plain `codex exec`. Use Codex's approval-routing option for those runs instead of `-s`, and tell the
  model in the brief that the server IS configured ("list your MCP tools first") — it sometimes claims
  a server isn't installed.
- Never `--dangerously-bypass-approvals-and-sandbox`. Never `pkill -f` a codex pattern — kill by PID.

## 3. Verify before reporting (Claude's half)

Read `codex-last.md`, then `git -C <repo> diff --stat`. Then actually prove it: run the tests, curl the
endpoint, screenshot the element. If the diff touches files outside the brief's scope, say so and offer
`git checkout -- <file>`. Do NOT commit on Codex's behalf.

**Optional review gate:** for apps where a bad deploy costs money, have a PreToolUse hook refuse the
restart/deploy command unless a fresh marker file exists (e.g. `/tmp/codex-review-<app>` under 90 minutes
old), and only `touch` that marker after `/codex review` comes back with no high-severity findings.
Never write the marker without a review.

**Parallel lanes:** independent components → separate `codex exec` runs in the background (distinct
`-o` files and slugs). Claude does MCP/verification work while they run; never wait idle.

## 4. Report in ≤5 lines, then log the lesson
What changed, how it was verified, anything Codex flagged, what's left for the human. Append ONE line
to a playbook notes file (date · task · what worked/failed · the brief or flag change that fixes it) and
read it before writing the next brief.

## When NOT to use
Design direction and taste calls, anything that needs Claude's own MCP tools, anything that reads
secrets, and any outbound send (email, messages, posts) — those stay with Claude and the human.
