---
name: signoff
description: Verify a phase is complete - traceability, open bugs, findings, escalations, evidence - then open or update the phase PR.
disable-model-invocation: true
---
1. Run the gap check: `bash <plugin>/scripts/signoff-check.sh`, where <plugin> is
   the folder two levels above this SKILL.md. It reads the phase named in
   .claude/current-phase and exits 1 with every gap listed. If it lists gaps,
   stop: show them, say who owns each (product, lead, QA), and do nothing
   else. If you can't run it, make the same checks by reading every one of
   acceptance-criteria.md, test-plan.md, qa-report.md, signoff.md,
   questions.md and the feature's .plumbline. Check all six rules below
   before answering, then list every gap found (not just the first) and stop.
   A waiver line counts only when it has no `<...>` placeholder left and ends
   with "(approved by <name>)" with a name filled in.
   - an AC ID in acceptance-criteria.md without a passing test in test-plan.md
   - a qa-report.md verdict other than PASS, or an open high or critical bug
   - an open Product finding, or an open high Design finding, in signoff.md
   - an OPEN or ESCALATED item in questions.md
   - an unticked sign-off box other than the PR and merge lines (an unticked
     Design verification box, on older features, doesn't count)
   - only with `surfaces=` in .plumbline: for each surface listed (a name is
     a kind, or `<kind>-<name>` such as web-ui-shop; any other name is a gap),
     its evidence kind below needs a qa-report.md Evidence row with that Kind,
     that Surface as written in `surfaces=`, a filled-in Location, and Result
     pass (a pass row with an empty Location doesn't count, and if any row for
     that kind and surface says fail, it is a gap even beside a pass row), or an
     "Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)"
     line (the dash may be `-`, `—` or `:`). Only the user approves a waiver;
     agents never write one. One kind per surface:
     web-ui and desktop-ui: journeys; mobile-ui: flow-tests; api: transcripts;
     service: job-tests; cli: golden-output; library: doc-examples; data:
     sample-run; ai: eval-set; infra: plan-output
2. With no gaps, run the full test suite. If it passes, push the branch and open
   (or update) the phase PR with a summary from qa-report.md and signoff.md in
   the body, and add the PR link to signoff.md. Never merge it; the user merges.
