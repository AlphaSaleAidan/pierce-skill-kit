# skill-recommender

On a substantial prompt, and again when the same task fails twice, it tells Claude which installed skills fit and
has it ask you once, in one line:

```
Switch to `lip-sync-and-gaze-qc`?
```

You answer, Claude follows. It stays quiet on short replies ("yes", "ok", "send it"), slash commands, skills already
loaded in the session, and anything it has already suggested in that session.

## Install
```sh
mods/install.sh skill-recommender              # adds 3 hooks to your Claude settings.json (a .bak is kept)
mods/install.sh skill-recommender --uninstall
```
Restart Claude Code afterwards. Needs Node and the skill index that `skill-route-sync` writes (the installer runs it).

## How it decides
- **Index:** `~/.claude/skill-index.json` (name, description, category of every installed skill), rebuilt by
  `skill-route-sync` on install, on `lead update` and daily. New skills are picked up automatically.
- **Tough task?** A work verb (build, fix, debug, design, deploy, render, …), a problem report ("looks fake",
  "not working", "lip sync drift"), or a long prompt. Approvals and chit-chat never fire.
- **Match:** local keyword scoring (BM25) over skill names and descriptions. A suggestion needs matched words that sit
  together in your prompt, one of them a distinctive word from the skill's name; long prompts need more matches.
  Apple-only skills need an Apple word in the prompt; web skills stay out of Apple prompts. At most 3, all close to
  the best score. No network, no API.
- **Mid-task:** the `PostToolUse` / `PostToolUseFailure` hooks count failed tool calls since your last prompt; on
  the second, it matches your task plus the error text and suggests a switch the same way.

## Tuning
| Env var | Default | What |
|---|---|---|
| `SKILL_REC_MIN` | 9 | score a suggestion must reach |
| `SKILL_REC_STOP` | none | extra words to ignore, comma-separated (your name, project names that appear in many skills) |
| `SKILL_REC_IGNORE` | `terminal-lead,project-tab,using-superpowers` | skills never suggested (ones that are always on anyway) |
| `SKILL_REC_OFF` | unset | `1` silences it without uninstalling |
| `SKILL_REC_DIR` | `~/.cache/skill-recommender` | state and log |

Try a prompt without Claude: `node ~/.config/pierce-skill-kit/mods/skill-recommender/recommend.js match "the green screen composite looks pasted on"`.

## Log
Every suggestion and how it was answered (accepted / declined / ignored) goes to `~/.cache/skill-recommender/log.jsonl`.
Prompts are stored as a short hash, never as text. Weekly line:

```sh
node ~/.config/pierce-skill-kit/mods/skill-recommender/recommend.js stats      # last 7 days
```

## Tested
54 prompts: 24 real past prompts, 20 short replies, 10 written tasks; graded by an independent reviewer.
Results are in the changelog entry for v0.4.0. Keyword matching misses some fits (it doesn't know "landing page" means
website-build); it's tuned to stay quiet rather than guess.
