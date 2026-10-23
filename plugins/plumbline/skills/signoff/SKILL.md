---
name: signoff
description: Verify a phase is complete - traceability, open bugs, findings, escalations - then open or update the phase PR.
disable-model-invocation: true
---
1. Run the gap check: `bash <plugin>/scripts/signoff-check.sh`, where <plugin> is
   the folder two levels above this SKILL.md. It reads the phase named in
   .claude/current-phase and exits 1 with every gap listed. If it lists gaps,
   stop: show them, say who owns each (product, design, lead, QA), and do
   nothing else. If you can't run it, make the same checks by reading every one
   of acceptance-criteria.md, test-plan.md, qa-report.md, signoff.md and
   questions.md. Check all five rules below before answering, then list every
   gap found (not just the first) and stop:
   - an AC ID in acceptance-criteria.md without a passing test in test-plan.md
   - a qa-report.md verdict other than PASS, or an open high or critical bug
   - an open Product finding, or an open high Design finding, in signoff.md
   - an OPEN or ESCALATED item in questions.md
   - an unticked sign-off box other than the PR and merge lines
2. With no gaps, run the full test suite. If it passes, push the branch and open
   (or update) the phase PR with a summary from qa-report.md and signoff.md in
   the body, and add the PR link to signoff.md. Never merge it; the user merges.
