---
name: signoff
description: Verify a phase is complete - traceability, open bugs, findings, escalations, accessibility - then open or update the phase PR.
disable-model-invocation: true
---
1. Run the gap check: `bash <plugin>/scripts/signoff-check.sh`, where <plugin> is
   the folder two levels above this SKILL.md. It reads the phase named in
   .claude/current-phase and exits 1 with every gap listed. If it lists gaps,
   stop: show them, say who owns each (product, design, lead, QA), and do
   nothing else. If you can't run it, make the same checks by reading every one
   of acceptance-criteria.md, test-plan.md, qa-report.md, signoff.md, ux.md,
   questions.md and the feature's .plumbline. Check all seven rules below
   before answering, then list every gap found (not just the first) and stop.
   A waiver line counts only when it has no `<...>` placeholder left and ends
   with "(approved by <name>)" with a name filled in.
   - an AC ID in acceptance-criteria.md without a passing test in test-plan.md
   - a qa-report.md verdict other than PASS, or an open high or critical bug
   - an open Product finding, or an open high Design finding, in signoff.md
   - an OPEN or ESCALATED item in questions.md
   - an unticked sign-off box other than the PR and merge lines
   - in qa-report.md's Accessibility table, any Critical or Serious count above
     0 or not a number. Then, without `surfaces=` in .plumbline: no rows at
     all while ux.md lists screens. With `surfaces=`: a web-ui surface and no
     row with Method axe, or a mobile-ui or desktop-ui surface and no row with
     Method checklist. Surfaces with no UI are exempt. An
     "Accessibility waived:" line clears the missing rows, not the counts.
   - only with `surfaces=` in .plumbline: for each surface listed (a name is
     a kind, or `<kind>-<name>` such as web-ui-shop; any other name is a gap),
     each evidence kind below needs a qa-report.md Evidence row with that Kind,
     that Surface as written in `surfaces=`, and Result pass, or an
     "Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)"
     line (the dash may be `-`, `—` or `:`). Several surfaces need every kind
     of each:
     web-ui: screenshots, axe, journeys; mobile-ui: screenshots, flow-tests,
     checklist; desktop-ui: screenshots, checklist; api: contract, authz,
     negative, transcripts; service: job-tests, failure-cases; cli:
     golden-output; library: doc-examples, api-diff; data: sample-run,
     idempotency; ai: eval-set, injection; infra: plan-output
2. With no gaps, run the full test suite. If it passes, push the branch and open
   (or update) the phase PR with a summary from qa-report.md and signoff.md in
   the body, and add the PR link to signoff.md. Never merge it; the user merges.
