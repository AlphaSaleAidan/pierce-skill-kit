# Memory and context: making Claude remember across sessions

Sessions end, contexts get compacted, tabs get closed. Anything that only lives in a chat is gone. The fix is
boring: **write it to a file, keep an index, re-read it.** Two layers do this: *memory* (what Claude has
learned) and *working context* (what's in flight right now).

## 1. File memory
A memory folder (Claude Code keeps one per project under `~/.claude/projects/<project>/memory/`).

- **One fact per file**, with frontmatter:
  ```markdown
  ---
  name: deploy-check-link
  description: check which hosting project a folder is linked to before any deploy
  type: feedback        # user | feedback | project | reference
  ---
  Run the link check before every deploy.
  **Why:** a folder linked to the wrong project deploys over a different site.
  **How to apply:** before `deploy`, print the linked project id and compare it to the brief.
  ```
- **Types:** `user` = who the human is and how they like to work · `feedback` = corrections and confirmed
  approaches · `project` = state, goals, deadlines · `reference` = where things live (dashboards, tickets).
- **An index, `MEMORY.md`:** one line per memory, `- [Title](file.md): hook`. It's loaded into every session,
  so keep it **under ~200 lines** (long indexes get truncated); detail lives in the topic files.
- **Link memories** with `[[name]]` so related facts get found together.
- **Newer wins.** When a fact changes, update its file, don't add a second one. **Delete memories that turn out wrong.**
- **Absolute dates** ("2026-10-13", not "yesterday"): relative dates rot the moment the session ends.

## 2. What to save, and what not
| Save | Don't save |
|---|---|
| Corrections, with **why** and **how to apply** | Anything the repo or git history already records |
| Approaches the human confirmed ("yes, do it this way") | Code structure (read the code) |
| Project state, goals, deadlines, who's waiting on what | Things that only matter to this one conversation |
| Pointers to external systems | **Secrets.** Store the *path* to the key file, never the value |

## 3. Hard rules at the top of the index
The first lines of `MEMORY.md` are a short **hard-rules block**: the handful of rules that cost real money or
trust when broken, each pointing to its memory file. Add one line telling Claude to **read the file before acting**:
the index line is a pointer, not the rule.

**Incident → rule.** Every costly mistake becomes (1) a one-line rule and (2) a memory file with the why and how
to apply. That's where [RULES.md](../RULES.md) came from.

**CLAUDE.md vs memory:** CLAUDE.md holds rules that apply everywhere, always (the rules sheet, how to talk to the
human). Memory holds what was *learned*: facts, per-project state, one-off corrections. If a memory keeps
mattering in every project, promote it into CLAUDE.md.

## 4. Working context in long sessions
The kit's files are what let a lead run for days:

| File | Survives because |
|---|---|
| `briefs/MMDD-<project>-<task>.md` | the task lives on disk, not in a chat message; a tab re-reads it after compaction |
| `decisions.md` | the human's decisions are quoted once, so a later session doesn't reverse them |
| `reports.tsv` | every result + proof, in order; "where are we" comes from here, not recall |
| `orders.tsv` | every ask, open until closed with proof |
| `retired-tabs.md` | one line per closed tab with its **resume id**, so the work can be picked back up |

Habits:
- After a compaction or a long break: **re-read the brief** before the next step.
- Answer status questions from the files (`order list`, the tail of `reports.tsv`), not from memory.
- Per-project memory folders keep one project's facts from leaking into another's decisions.

## 5. Optional: search over memory
Past a few hundred memories, the index can't list everything. A local vector index over the memory folder lets
a session search by meaning ("anything about deploy links?"). It's optional; a tidy index plus `grep` goes a long way.
