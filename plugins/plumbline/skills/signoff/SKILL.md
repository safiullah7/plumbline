---
name: signoff
description: Verify a phase is complete - traceability, open bugs, findings, escalations - then open or update the phase PR.
disable-model-invocation: true
---
Read the phase folder named in .claude/current-phase. Stop and list every gap if:
- any AC ID in acceptance-criteria.md has no passing test in test-plan.md
- qa-report.md has a verdict other than PASS, or an open bug of severity high or
  critical
- signoff.md has an open Product finding, or an open Design finding of severity
  high
- questions.md has any OPEN or ESCALATED item
- a sign-off checkbox other than the PR and merge lines is unticked

Otherwise run the full test suite. If it passes, push the branch and open (or
update) the phase PR with a summary from qa-report.md and signoff.md in the
body, and add the PR link to signoff.md. Never merge it; the user merges.
