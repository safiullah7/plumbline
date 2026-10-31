---
name: status
description: Show the active phase at a glance - plan status, AC test coverage, open bugs, questions and uncommitted work per owner.
disable-model-invocation: true
---
Run `bash <plugin>/scripts/status.sh`, where <plugin> is the folder two levels
above this SKILL.md, and show its output exactly as printed. Then add at most
three lines: what blocks signoff right now and who owns it. During a team
build, the `team:` line shows each teammate's open and ready tasks from the
shared task list. Call a teammate stalled only when
`bash <plugin>/scripts/watch-build.sh` prints a `STALLED:` line for it; a
`LEAD:` line lists the lead's open chores, and `NO-TASKS` means the lead
hasn't created the task list yet. Don't read the phase docs to answer; the
script already summarises them.
