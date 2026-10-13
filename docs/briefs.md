# Briefs: one file per task

The lead never types long instructions into a tab. It writes a brief file and sends one line pointing at it:

```sh
brief-send acme-app ~/.pierce-skill-kit/briefs/1013-acme-app-checkout-fix.md
```

The tab receives: *"Brief from the lead: read <file> and follow it (skill: project-tab). Report … with: report …"*.

## Rules
- **One file per task**, named `MMDD-<project>-<task>.md`. Never one ever-growing file per project.
- **Sections:** GOAL · CONTEXT · DONE-WHEN · LIMITS · REPORT. Template: [templates/brief.md](../templates/brief.md).
- **Quote the human verbatim** for the ask itself. Paraphrase loses intent.
- **Follow-ups that change an in-flight task** go in an `## UPDATE n` section at the bottom of *that* brief,
  again quoting the human. Say priority changes explicitly: "PRIORITY: do X before Y".
- **DONE-WHEN is checkable:** a URL that loads, a test that passes, a count. Not "it works".
- **LIMITS name the approvals:** what the tab may not do without the human (send, deploy, spend, delete).

## Decisions log
Every decision the human makes goes into the brief it affects *and* one line in `$LK_HOME/decisions.md`:
`| when | project | decision | why | how to undo |`. It's what keeps a later session from reversing it.
