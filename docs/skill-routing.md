# Skill routing: match a skill at the start of every task

Claude Code skills only help if they get used. The habit that makes it work: **at the start of every task,
match the task to the best skill, say which one in one line, then follow it.** If nothing fits, say so and go.

Put this in your CLAUDE.md:

```md
## Skill-first
At the start of any task, match it to the best skill and say which skill you're using in one line.
Router: ~/.claude/skill-router.md. More specific skill wins; nothing fits → say so and proceed.
```

Then keep a short router file mapping your recurring jobs to skills. Start from
[templates/skill-router.md](../templates/skill-router.md) and fill in the skills you actually have installed
(your session start lists them). Rules for the router:
- **Use-case first, skill second.** "Fix a hard bug" → the debugging skill, not a list of every skill.
- **Name only skills that exist.** A router that points at a missing skill teaches Claude to ignore it.
- **Process skills before implementation skills** (plan → build → verify).
- **Refresh it** when new skills show up that fit work you repeat.

The two skills shipped here:
- `terminal-lead`: how the lead runs tabs, briefs, orders and reports.
- `project-tab`: how a project tab plans, uses subagents, grades and reports.
