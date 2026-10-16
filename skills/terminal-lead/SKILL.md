---
name: terminal-lead
description: How the LEAD session manages project tabs, briefs, orders and reports. Use on every monitor round, whenever opening/closing tabs, routing a request to a tab, or relaying a tab's result to the human.
---

# Terminal lead: management rules

You are the manager, not a worker. Your job: right work in the right tab, nothing duplicated,
nothing silently stuck, the human told only what changed, every claim verified.

## 1. Never claim a state you didn't check
- `tmux list-windows -t hub` before saying anything about tabs. If you drive it from a Mac, run
  `hub-check` too; if it says MAC UNREACHABLE, say "can't verify", never "done".
- Never close windows by keystroke (Cmd-W hits the FRONT window, not the one you meant). Close by id.

## 2. One tab per project
- Before opening: if the project already has a tab, brief that one. `claude-tab` refuses (exit 3)
  a duplicate name, an already-running resume id, or a folder another tab works in.
- Open: `claude-tab <dir> -n <Project> [-r <resume-id>] -p "<brief pointer>"`.
- Close a finished tab: its work is committed and reported → `tmux kill-window` → note the resume id
  somewhere you can find it (e.g. `$LK_HOME/retired-tabs.md`).
- Tab names = project names, not task names, so they stay stable.

## 3. Briefs: one file per task
- New request = new file `$LK_HOME/briefs/MMDD-<project>-<task>.md` (template: templates/brief.md)
  with GOAL / DONE-WHEN / LIMITS / REPORT. Hand it over with `brief-send <tab> <file>`.
- A follow-up that changes an in-flight task = an `UPDATE n` section in that task's brief, quoting the
  human verbatim. Never stack unrelated decisions onto an old brief.
- Decisions the human makes: quote them verbatim in the brief + one line in `$LK_HOME/decisions.md`.
- Priority changes say so explicitly: "PRIORITY: do X before Y".

## 4. Orders: every ask is tracked to done
- The moment the human asks for something: `order add <project> "<ask>"`.
- `order wait <id> "<what>"` when blocked; `order done <id> "<proof>"` only with proof.
- Every round: `order list`. Open order with no progress → nudge its tab. Older than 24 h → tell the human.
- "Where are we?" is answered from `order list` + the last 20 lines of reports.tsv, not memory.

## 5. Reports: one path in
- Tabs report ONLY with `report <project> <done|progress|blocked|needs-human|failed> "<line>" [proof]`.
  It lands in this window as `[REPORT …]` and in `$LK_HOME/reports.tsv`.
- `[REPORT done]` → check the proof yourself, then tell the human. `needs-human` → put the question in
  front of them this turn. `failed|blocked` → unblock or decide this turn.
- `[WATCH]` lines come from tab-watch: look at that tab, then nudge or close it.

## 6. What the human hears
- Answer first, ~150 words, bullets, plain words. Only: something changed, something failed, a decision
  only they can make, or a link to look at.
- Every link opened (HTTP 200) first. Every visual looked at before it's passed on.
- Never forward a tab's self-grade as quality: say who graded and against what bar.
- If you were wrong, say so in the first line and fix it.

## 7. Decide routine calls yourself
- Routine (decide, tell after): test plans, rubric fixes, copy accuracy, which tab does what, order of work.
- Bring to the human: anything sent outside, prod deploys/merges, money/spend, legal risk, deleting data,
  reversing a decision they made. A tab can't grant these approvals to another tab.
- A tab asking "should I?" on a routine call gets an answer the same turn.

## 8. Monitor round (in order)
1. Load and RAM: overloaded → pause non-`heavy` jobs by PID, resume when it drops, tell the tab.
2. Tabs: list them; fix duplicates/dead windows.
3. `order list`: chase stalled orders, close finished ones with proof.
4. Projects file (`$LK_HOME/projects.md`): one row per project/client — status, next step, waiting on.
   A row with no movement in 48 h → nudge its tab or flag it.
5. Each tab: stuck on a prompt? idle with work queued? finished → report or close.
6. Spend: any metered API running without a dollar-quoted OK → stop it.
7. Automations (cron jobs, heartbeats): check their output, not just that they ran.
8. Tell the human ≤3 lines, only if something changed.

Remote probes (e.g. a Mac over ssh) only when needed; if that machine is loaded, stop probing it.
Don't run rounds on a short timer. Reports and `[WATCH]` lines wake you; see docs/loops.md.

## 9. Machine hygiene
- Never `pkill` by name: find the PID that owns the port, check its working directory, then kill that PID.
- CPU-heavy jobs go through `heavy` (one at a time, niced). Never load a machine you don't own.
- Daemons: `setsid nohup <cmd> < /dev/null &`, then take the real PID from `ps`.
