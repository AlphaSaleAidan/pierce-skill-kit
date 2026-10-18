---
type: "rule"
memory_type: "feedback"
description: "Never report done without a checked link or a screenshot path; two thin \"done\" reports on acme-site had to be redone"
source: "memory/feedback_proof_before_done.md"
modified: "2026-10-11T08:00"
title: "Never report done without a checked link or a screenshot path; two thin \"done\" reports on…"
---
<!-- brain:generated (rebuilt on every refresh; write your own notes below the end marker) -->
# Never report done without a checked link or a screenshot path; two thin "done" reports on…

> Never report done without a checked link or a screenshot path; two thin "done" reports on acme-site had to be redone

Every `done` report names its proof: a link that was opened and returned 200, a screenshot path, or a commit hash.

**Why:** two "done" reports on acme-site said the page was live when the deploy had failed.

**How to apply:** check the link yourself before you report, and paste it as the proof argument.

source: `memory/feedback_proof_before_done.md`
mentions: [[acme-site|Acme site]]

## Backlinks (1)
- [[acme-site-context|Acme wants checkout live before their 2026-10-24 promo; Dana Example approves all copy]]
<!-- /brain:generated -->
