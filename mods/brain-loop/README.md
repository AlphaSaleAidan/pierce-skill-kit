# brain-loop: the Obsidian + Opus + Jev loop

Plan → act → observe → improve, around the lead. The short version and the measured numbers are in the
[main README](../../README.md#obsidian--opus--jev-loop). This page is the reference.

Needs python3 (standard library only). Jev is optional and off by default.

| Piece | What it does | Command |
|---|---|---|
| Vault | Obsidian-compatible folder: one note per project, person, ask, money item, decision, plan and rule, `[[links]]` both ways, generated Backlinks, open asks in chase order. `.brain.json` holds the graph | `brain-loop build`, `open`, `show NAME` |
| Hand overrides | `my_status`, `my_owner`, `my_chase_after`, `my_note`, `my_link`, `my_title` in a note's frontmatter, plus any text below `<!-- /brain:generated -->`, survive every rebuild and win | `brain-loop mark ID --status done --note "..."` |
| Router | Triage of each new report: needs_owner, blocked, done_proven, has_next, urgency, plan, rows. Confident (0.9+) answers are written; 0.5-0.9 go to the lead in one message per run | `brain-loop route dryrun\|shadow\|run --apply\|score\|preview` |
| Plan grade | Scores each `Dn.` direction of a plan followed / partly / not followed from the evidence; unsure Jev answers go to a headless Sonnet check | `brain-loop grade PLAN.md [--dry] [--write]`, `grade weekly --write` |
| stuck-check | Re-raises a project whose latest report is needs-human / blocked / failed after 20 min, and each overdue plan checkpoint, once each | `brain-loop stuck` |
| MCP server | `brain(entity)`, `brain_open(owner, kind, limit)`, `brain_mark(id, ...)` over stdio | `claude mcp add -s user brain -- ~/.local/bin/brain-loop mcp` |
| /brain page | Force graph (d3 from cdnjs), open-items filter, note panel, open list. Read-only, 127.0.0.1 only | `brain-loop page [--port 8790]` |
| SessionStart hook | The lead (a session started in `LK_LEAD_DIR`) gets the top 15 open items; a tab whose folder name matches a project gets that project's open items | added by `mods/install.sh brain-loop` |
| Plans | `brain-loop plan-new <project> <task> [tab]` copies the `tab-plan` template to `$BRAIN_PLANS/<project>/MMDD-<task>.md` | send it with `brief-send <tab> <plan>` |

## Inputs (all from the config)
`bin/brain-loop` loads the kit config (`lk-config`, `$LK_CONFIG`), so every path is a `BRAIN_*` line in
`~/.config/pierce-skill-kit/config` (see `config.example`). Defaults live under `$LK_HOME`:

| Var | Default | What it is |
|---|---|---|
| `BRAIN_ENTITIES` | `$LK_HOME/brain-entities.json` | Your projects and people with aliases and emails (format: [examples/brain-loop-inputs/entities.json](../../examples/brain-loop-inputs/entities.json)). `case_sensitive` lists short names that are also ordinary words, matched only with that exact case. Aliases you add to a note's frontmatter are merged back in |
| `BRAIN_REPORTS` | `$LK_HOME/reports.tsv` | Written by `report`. needs-human reports from the last 7 days become "waiting on the owner" items |
| `BRAIN_ORDERS` | `$LK_HOME/orders.tsv` | Written by `order`. Each order is an ask |
| `BRAIN_DECISIONS` | `$LK_HOME/decisions.md` | `2026-10-10 acme-site: text` lines, or `\| when \| project \| goal \| decision \| why \| undo \|` rows |
| `BRAIN_PLANS` | `$LK_HOME/plans` | Plan files (`tab-plan`). Orders listed under `## Rows` get the plan's tab as owner |
| `BRAIN_MEMORY_DIRS` | none | Colon-separated Claude memory folders. `type: feedback` files become rules |
| `BRAIN_LEDGER` | none | Optional money TSV: `id added direction(in\|out) who what amount due status project note`. open/overdue = owed now, pending = not counted |
| `BRAIN_VAULT` | `$LK_HOME/brain` | Where the vault is written |
| `BRAIN_ROUTER_DIR` | `$LK_HOME/brain-loop` | Router state, logs, `applied.keys`, the `OFF` switch, `spend.jsonl`, plan-grade output |
| `BRAIN_JEV_CAP_USD` | `0` (off) | Monthly dollar cap for Jev; also `BRAIN_JEV_DAY_ALERT_USD` (default cap/10) |
| `BRAIN_OWNER` | `owner` | What notes call the human |
| `BRAIN_SAY` | type into the lead's tmux window | A command that gets each message for the lead as `$1` |

Jev uses the same key file and model as `report-check`: `LK_CHECK_KEY_FILE` (a line `OPENROUTER_API_KEY=...`) and
`LK_CHECK_MODEL`. The key is never printed or logged; every note's text passes a secret mask, and nothing under
`.secrets` or a `.env` file is read.

## Cron
```
*/15 * * * * $HOME/.local/bin/brain-loop build >/dev/null 2>&1 # pierce-skill-kit brain-loop
*/15 * * * * $HOME/.local/bin/brain-loop route run --apply >/dev/null 2>&1 # pierce-skill-kit brain-loop
*/20 * * * * $HOME/.local/bin/brain-loop stuck >/dev/null 2>&1 # pierce-skill-kit brain-loop
0 9 * * 1 $HOME/.local/bin/brain-loop grade weekly --write >/dev/null 2>&1 # pierce-skill-kit brain-loop
```
`touch $LK_HOME/brain-loop/OFF` pauses the router without touching cron. The first router run starts at the end of
`reports.tsv` (it never replays your history); `--since LINE` replays on purpose, and an action already applied is
never written twice.

## Engines
- `stub` (default): rules only, free. Urgency is never confident, so it never acts alone.
- `jev`: Jev answers needs_owner, blocked, done_proven, urgency and plan; has_next and rows stay rule-based.
- `hybrid`: both, per field. A confident source wins; two confident sources that disagree go to the lead.
  If Jev is down or the cap is hit, the run falls back to the rules and says so.

Measure it on your own data before you trust it: label 40-60 reports by hand as JSON lines
(`{"line": 12, "needs_owner": true, ...}`), run `brain-loop route dryrun --engine hybrid`, then
`brain-loop route score gold.jsonl`. It prints accuracy per field, overall and on the confident answers only.

## What's not here
A full-text or vector search daemon: the vault, the MCP tools and the kit's `lead-recall` cover lookups. Business
specific inputs (a money app's own database, an audit spreadsheet) are replaced by the generic ledger TSV.

## Test
`docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/brain-loop-test.sh` builds the example vault
and diffs it against `examples/brain-vault`, then runs the router, plan-grade (against a fake local Jev and a stub
Claude), the MCP server, the page, the hook, stuck-check and the installer. No network.
