# Model routing: spend tokens where they change the outcome

Your weekly usage is a budget. The top model costs several times more per token than the mid model, and
the mid model several times more than the small one. Most work in a busy setup is *not* hard: reading
logs, sweeping files, checking that something rendered. Route it down and keep the top model for the
calls where being smarter actually changes the result.

## The tree

```
Is it a decision only the human can make (send, deploy, spend, legal)?
└─ yes → don't route it. Report needs-human.

Does a wrong answer cost money, data, or trust?   (payments, auth, migrations, anything a client sees)
└─ yes → STRONGEST model builds it AND a separate strongest-model reviewer checks it.

Is it a hard build or a judgement call?            (new system, tricky bug, design taste, grading)
└─ yes → STRONGEST model.

Is it parallel, well-specified work?               (a lane in an existing pattern, tests, research,
                                                     verification, re-review after a fix)
└─ yes → MID model, as a subagent with a full brief.

Is it mechanical or a lookup?                       (rename, format convert, "which file has X")
└─ yes → SMALL model (or just a shell command; that's free).
```

The **lead** session itself runs on the strongest model: it makes routing calls, reads reports and
decides what reaches the human. It does no project work, so its token use stays small.

## Why each split saves tokens
- **Lead on the top model, tabs doing the work:** the lead's context stays small (reports, not file
  dumps), so its expensive tokens buy judgement, not reading.
- **Subagents for reading:** a subagent that sweeps 40 files returns a 10-line conclusion. The file
  contents never enter the parent's context, which would otherwise be re-read every turn.
- **Mid model for verification:** checking "did the screenshot render, does the test pass" needs eyes,
  not brilliance.
- **Brief files over long prompts:** a tab reads the brief once from disk; the lead never has to retype it.

## Caps that keep it in budget
- ≤3 subagents per tab at once; ≤1 of them CPU-heavy, via `heavy`.
- Grading loops: ≤3 rounds (see [loops.md](loops.md)).
- **Never poll.** A 60-second wait loop re-reads the whole context every minute. Wait on an event or one
  long watch instead.
- If every account you have is past ~90% of its weekly limit, stop starting new lanes and tell the human.

## When a model refuses
Most refusals on legitimate work come from missing context, not from the task. Handle them in the product, never
by arguing the model past its limits. No jailbreaks, no "the rules don't apply here", no rewording to sneak a
request through: if the request is outside a model's policy, the answer is no, and the product should say so plainly.

1. **Context up front.** In the system prompt or brief, state the real purpose, the audience and the boundaries.
   Example: *"Harm-reduction app for adults: give sourced safety facts; never give sourcing or buying information."*
   Clear boundaries make the legitimate part easy to answer.
2. **A fallback, not a dead end.** When an answer is refused, the app shows verified, sourced content it already
   has (e.g. pre-checked answer cards with citations) and says that's what it's showing.
3. **Route, log, flag.** A legitimate task one model declines can go to a model better suited to it (e.g. a larger
   model for a nuanced medical question). Log the refusal and the route, and flag it to the human.
   **One reroute, then stop:** if the second model also declines, treat that as the answer.
4. **Repeated refusals on one topic = fix the context or the product,** not the model. Read the logs weekly;
   a cluster of refusals means the prompt is unclear or the feature is asking for something it shouldn't.

## Example (Claude Code model names as of writing)
| Job | Model |
|---|---|
| Lead session, hard builds, money-path code, grading, final review | Opus |
| Parallel lanes, research, verification, test writing, re-reviews | Sonnet |
| Trivial lookups, mechanical sweeps | Haiku |

Pick a model per subagent with the Agent tool's `model` option, or per tab with `claude-tab -m <model>`.
