---
name: tab-plan
description: Lead only. Before sending ANY instruction to a project tab, write a full plan .md (goal, done-when proof, numbered directions, rules, timed checkpoints, owner decisions, next steps) and send the tab only a pointer to it. The lead then follows the same plan - ticks each checkpoint when due, logs progress in the file, chases misses, and grades compliance at close. Use for every new task AND every follow-up (follow-ups = a new UPDATE section in the same plan).
---

# tab-plan: one plan file per project task, followed by both the tab and the lead

A bare chat message to a tab gets half-read, can't be checked later, and is gone after a context compaction. A plan
file is the contract: what to do, how to prove it, when the lead checks, and what was decided. It is also what the
brain-loop mod reads (`mods/brain-loop/README.md`): the router logs reports into it, `stuck-check` raises overdue
checkpoints, and `brain-loop grade` scores how well the tab followed it.

## Rules
1. **No bare messages to tabs.** Every instruction lives in a plan file. The tab gets one line:
   `brief-send <tab> <plan.md>`. The only exception: answering a yes/no the tab asked, which you also log in the
   plan's Progress log.
2. **One plan per project task**: `brain-loop plan-new <project> <task> [tab]` creates
   `$BRAIN_PLANS/<project>/MMDD-<task>.md` from [template.md](template.md). Follow-ups append
   `## UPDATE n (date, source)` to the same file, never a new message.
3. **Fill every section** before sending. A plan with an empty Done-when, no Directions or no checkpoints is not
   sendable.
4. **Done-when = the real effect** (the person-facing result, proven: link checked, screenshot path, email fetched
   back). "Tests pass" is never done-when.
5. **Directions are numbered and checkable**: `D1. <exact instruction> | proof: <what shows it was followed>`. Each
   one is graded followed / partly / not followed at close.
6. **Checkpoints are timed**, exact form `- [ ] CP<n> due YYYY-MM-DDTHH:MM | <what the lead expects> | <proof>`
   (UTC). `stuck-check` tells the lead when one is past due; the lead then checks the tab and either ticks it
   (`- [x]` + proof) or chases/escalates the same turn.
7. **The lead follows its own plan**: on every report, open the plan, tick checkpoints with proof, append one
   Progress log line (the router does this for confident reports), and decide the next step from the plan, not from
   memory.
8. **Owner decisions** go in their own section with the date asked and the tab's recommendation. When the owner
   answers, move it to the Progress log as `ANSWERED <date>: <their words>` and record it in
   `$LK_HOME/decisions.md`.
9. **Rows**: list the order ids (`order list`) this plan takes over. The brain then shows the plan's tab as their
   owner, and the router marks them when a report proves them done.
10. **Close-out**: when Done-when is proven: Status DONE + proof, `order done <id> "<proof>"`,
    `brain-loop grade <plan> --write`, and close the tab if it has no other ACTIVE plan (`tab-sweep` does it safely).

## Research, then exact orders, then a grade
Before writing a plan, the lead researches: `lead-recall`, `brain-loop show <project>`, and a read-only research
subagent when needed. Jev is a decision model, not a web researcher: use it to rank or decide on facts already
gathered. At close, `brain-loop grade` scores every Dn from the evidence (reports, Progress log, files named in
proofs). Scores go to `$LK_HOME/compliance.tsv`; `brain-loop grade weekly --write` writes the most-missed directions
into a rule note in the vault. A direction missed twice becomes a standing rule in your next plans.

## Tab rules for the lead
1. One tab per project; open one only with a sendable plan. No plan, no tab.
2. After `brief-send`, check the tab actually picked it up (its screen shows it working). Never "sent" on faith.
3. A tab's mistake is the lead's: a wrong claim, an idle tab, a missed checkpoint, an unrelayed needs-human. Check
   proof before relaying, chase overdue checkpoints, own the explanation to the owner.
