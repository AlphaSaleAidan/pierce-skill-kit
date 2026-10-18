---
name: Proof before done
description: Never report done without a checked link or a screenshot path; two thin "done" reports on acme-site had to be redone
type: feedback
modified: 2026-10-11T08:00
---
Every `done` report names its proof: a link that was opened and returned 200, a screenshot path, or a commit hash.

**Why:** two "done" reports on acme-site said the page was live when the deploy had failed.

**How to apply:** check the link yourself before you report, and paste it as the proof argument.
