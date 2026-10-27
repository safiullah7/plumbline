---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
---

Judge the Tasks and the Team table. A task's complexity is LOW, NORMAL or HIGH. The lead's rubric rates HIGH: authorization, data separation between customer accounts, billing, migrations, concurrency and public contract changes; LOW is a small change in one place with no new logic. A [chore] task delivers no AC, so it may say "E2E: none" and name a check instead of an AC test; judge only the tasks that deliver AC IDs on the points about AC-named tests.

PASS if (1) every task that delivers AC IDs has Files, Red (unit), E2E, Change, Edge cases, Check and Done when lines, where Red (unit) and E2E name a test starting with an AC ID and Done when says those AC IDs' unit and e2e tests pass; (2) every task carries a LOW/NORMAL/HIGH rating, and the api workstream task that enforces authorization or tenant data separation (AC-01-003 or AC-01-004) is rated HIGH (a web task that only shows or hides UI is not that enforcement and may be NORMAL); (3) each engineer's Effort in the Team table equals its highest task rating (LOW is low, NORMAL is medium, HIGH is high); (4) the plan covers AC-01-001 to AC-01-005.
FAIL if an AC task lacks the unit test, the e2e test or Done when, a task has no rating, an Effort disagrees with the engineer's highest-rated task, or the plan tells engineers to write code before the failing test.
