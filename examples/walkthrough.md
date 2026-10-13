# Walkthrough: a lead and two tabs

```sh
lead -d                                   # start the lead (tmux session "hub", window "Lead")
claude-tab ~/code/acme-app -n acme-app    # tab 2
claude-tab ~/code/data-sync -n data-sync  # tab 3
tab-view hub:Lead                         # look at the lead in this terminal (or just: lead)
```

The human tells the lead: *"fix the checkout bug on acme-app and get the nightly import green."*

The lead (skill `terminal-lead`):
```sh
order add acme-app "fix checkout bug"          # -> order #1
order add data-sync "nightly import green"     # -> order #2
$EDITOR ~/.pierce-skill-kit/briefs/1013-acme-app-checkout.md      # from templates/brief.md
brief-send acme-app ~/.pierce-skill-kit/briefs/1013-acme-app-checkout.md
brief-send data-sync ~/.pierce-skill-kit/briefs/1013-data-sync-import.md
```

The tabs work (skill `project-tab`) and report:
```
[REPORT done] acme-app (acme-app): checkout fixed, e2e green on preview | https://preview.example.com/checkout
[REPORT needs-human] data-sync (data-sync): source changed its date format; map it or ask them? Recommend map it
```

The lead opens the preview itself, then tells the human in three lines: checkout is fixed (link), and
one question about the import. `order done 1 "preview checked"`. `order wait 2 "date-format decision"`.

Forty minutes later the acme-app tab has gone quiet with nothing to do; the watchdog says so:
```
[WATCH] tab 'acme-app' (hub:2) is idle with no report in the last 60 min. Check it: finished, stuck, or waiting on the human?
```
The data-sync tab isn't flagged: its last report was `needs-human`, so it's waiting, not stuck.
