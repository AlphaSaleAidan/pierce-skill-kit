# Skill routing: match a skill at the start of every task

Claude Code skills only help if they get used. The habit that makes it work: **at the start of every task,
match the task to the best skill, say which one in one line, then follow it.** If nothing fits, say so and go.

Put this in your CLAUDE.md:

```md
## Skill-first
At the start of any task, match it to the best skill and say which skill you're using in one line.
Router: ~/.claude/skill-router.md. More specific skill wins; nothing fits → say so and proceed.
```

Then keep a short router file mapping your recurring jobs to skills. Copy
[templates/skill-router.md](../templates/skill-router.md) to `~/.claude/skill-router.md` and fill in the skills you actually have installed
(your session start lists them). Rules for the router:
- **Use-case first, skill second.** "Fix a hard bug" → the debugging skill, not a list of every skill.
- **Name only skills that exist.** A router that points at a missing skill teaches Claude to ignore it.
- **Process skills before implementation skills** (plan → build → verify).
- **Refresh it** when new skills show up that fit work you repeat.

The two lead/tab skills shipped here (the other 23 are indexed in [SKILLS.md](../SKILLS.md)):
- `terminal-lead`: how the lead runs tabs, briefs, orders and reports.
- `project-tab`: how a project tab plans, uses subagents, grades and reports.

## Keep the router current automatically: `skill-route-sync`
New skills arrive all the time (`npx skills add`, plugins, your own). `skill-route-sync` reads every installed
skill's `SKILL.md` (name + description) from `~/.claude/skills`, `~/.agents/skills` and your installed plugins, and:
- writes `~/.claude/skill-index.json` (name, description, category, which model should lead it);
- rewrites only the block between `<!-- skill-route-sync:auto start/end -->` at the bottom of
  `~/.claude/skill-router.md`: every installed skill your hand-written tables don't already name, grouped by category;
- prints new and removed skills since the last run.

The category is guessed from the name and description and marked **auto, review** until you confirm it:
`skill-route-sync --confirm <name> ["Design & web"]`. Your hand-written rows are never edited.

It runs on install, on every `lead update`, daily at 05:10 if you said yes during install, and after `skill-add`
(a wrapper: `skill-add <owner/repo> [--skill name]` = `npx skills add` + sync). `--dry-run` shows the change first.
Kit maintainers: `skill-route-sync --kit .` also checks every `skills/*` folder has a row in SKILLS.md and writes
`skills/index.json`.

## Get told when a better skill fits: the skill-recommender mod
`mods/install.sh skill-recommender` adds a hook that, on substantial prompts (and after a task fails twice), has
Claude ask you once: "Switch to `<skill>`?". It reuses the same index. Details and tuning:
[mods/skill-recommender/README.md](../mods/skill-recommender/README.md).
