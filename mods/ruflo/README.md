# Ruflo integration (optional)

[Ruflo](https://github.com/ruvnet/ruflo) (formerly [claude-flow](https://github.com/ruvnet/claude-flow), and still published under that name too) is ruvnet's agent
orchestration and memory layer for Claude Code. **This kit does not include Ruflo.** It is an
optional dependency: install it from upstream, then optionally apply the small patch in this folder.

Credit: Ruflo / claude-flow is by ruvnet and contributors, MIT licensed
(see the `LICENSE` file in the upstream repo). The patch here changes two upstream files. Those
patched lines stay under Ruflo's MIT license. The rest of this folder is under the kit's MIT license.

Tested against `ruflo` **v3.56.9**.

## Files

| File | What it is |
|---|---|
| `config-dir.patch` | 2-file patch for the helpers that `ruflo init` writes |
| `apply.sh` | Applies or reverts the patch. Safe to re-run. Backs up both files first |
| `settings.snippet.json` | The minimum hook wiring the memory bridge needs, if you wire by hand |

## 1. Install upstream

In each project you open as a tab (or once in `$HOME`; see "Lead and tabs" below):

```bash
npx ruflo@latest init                                    # writes .claude/ helpers, hooks, .mcp.json
claude mcp add claude-flow -- npx ruflo@latest mcp start # MCP server, if init did not register it
```

`init` already registers the MCP server in the project's `.mcp.json` and wires the hooks into
`.claude/settings.json`. Run `npx ruflo@latest init --help` to see the opt-out flags (for example
`--no-global` to leave `~/.claude/CLAUDE.md` alone, `--no-signup`, `--no-plugin-install`).

## 2. Apply the overlay

```bash
<KIT_DIR>/mods/ruflo/apply.sh <PROJECT_DIR>     # default: current directory
```

You need `patch` or `git`. The script does a dry run first. If the patch does not fit, it changes
nothing and exits 1. A second run prints `overlay already applied`. `ruflo init upgrade` and
`init --force` rewrite the helpers, so re-run `apply.sh` after either one.

### If the patch fails

A newer Ruflo moved the code. Check first whether upstream now reads `CLAUDE_CONFIG_DIR`
(`grep -n CLAUDE_CONFIG_DIR .claude/helpers/*.{cjs,mjs}`). If it does, you do not need this patch.
If it doesn't, the change is two lines; see the patch.

## 3. Uninstall / revert

```bash
<KIT_DIR>/mods/ruflo/apply.sh --revert <PROJECT_DIR>   # restores *.pierce-kit.bak
```

To remove Ruflo itself, follow upstream's instructions. In short: delete `.claude/helpers/`,
`.claude-flow/`, the Ruflo hooks in `.claude/settings.json` and the `claude-flow` entry in `.mcp.json`.

## What the patch changes

Claude Code keeps each project's auto-memory files under `~/.claude/projects/<project>/memory/`.
If `CLAUDE_CONFIG_DIR` is set (for example, one config folder per Claude account), they are stored under `$CLAUDE_CONFIG_DIR/projects/...` instead. Upstream always
looks in `~/.claude`, so for those tabs the memory bridge quietly imports nothing.

- `auto-memory-hook.mjs`: the bridge that copies auto-memory files into Ruflo's memory store at
  session start (`import`) and back at stop (`sync`). It now reads from `$CLAUDE_CONFIG_DIR` when
  that is set.
- `intelligence.cjs`: builds the ranked list of memories that the prompt hook shows as
  `[INTELLIGENCE] Relevant patterns`. Its first-run scan now also checks `$CLAUDE_CONFIG_DIR`.

Without `CLAUDE_CONFIG_DIR`, both files behave exactly like upstream.

## How it fits the lead/tabs setup

Each tab is its own Claude Code session running in its own project directory. The hooks run per tab:

- **SessionStart, `session-restore`**: picks the tab's Ruflo session state back up and loads the
  ranked memory, so a reopened tab starts with what it learned last time.
- **SessionStart, `auto-memory-hook.mjs import`**: copies the tab's Claude auto-memory files into
  Ruflo's memory store, where Ruflo's memory search tools (MCP) can find them.
- **UserPromptSubmit, `route`**: suggests an agent type and prints the top matching memories.
- **Stop, `sync`** and **SessionEnd**: write new insights back and close the session.
- **Ponytail mode** (the "lazy senior dev" coding-style prompt some tabs show at start) is **not
  part of Ruflo**. It comes from a separate Claude Code plugin with its own SessionStart hook, so
  it is not configured here.

Memory is per project. Tabs only share memories if they share a project directory. The hook commands
fall back to `$HOME/.claude/helpers/` when a project has no helpers of its own, so one `init` in
`$HOME` covers tabs that you never initialised individually.

## What was looked at and skipped

These came from a local Ruflo install that had drifted from upstream. Each one was checked against
a fresh `npx ruflo@latest init` (v3.56.9):

- **Failure capture in `hook-handler.cjs`** (post-edit and post-task record failed tool calls as
  negative examples): already upstream (ADR-174). Not shipped.
- **The rest of the local `hook-handler.cjs`**: an older fallback copy. Compared with current
  upstream it drops the hook timeouts and loads helper files by the wrong extension. Not shipped.
- **`auto-memory-hook.mjs`**: the local copy was upstream's minimal fallback, with no local
  edits. Not shipped.
- **`intelligence.cjs`** (git shows it as binary only because a dedupe key contains a literal NUL
  byte; it is plain JS, not a build artifact). It held two genuine local fixes, written against
  the old fallback version:
  1. Dedupe of memory sections. The old version scanned every project's memory, so the same
     text was imported hundreds of times. Upstream now scans only the current project and dedupes
     by id and by content. Not shipped.
  2. A faster scorer for that old matching code. Upstream now uses a different matching method,
     so the patch has nothing to apply to. Not shipped.
- **`settings.json`**: the hook wiring was the same as upstream's (upstream now wires more events).
  The other differences were personal: model choice, permission allow-lists, status line. Not shipped.
  `settings.snippet.json` is upstream's wiring with placeholders.
