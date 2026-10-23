---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-01/acceptance-criteria.md }
---

Judge only the rows for UC-01-03.

PASS if every UC-01-03 criterion is observable (UI text, a visible state, or an API status) and states the exact expected result, and together they cover: a successful deactivation shown as Inactive, reactivating a room, and a receptionist being unable to deactivate.
FAIL if any UC-01-03 criterion is vague (for example "works correctly" or "handles errors"), or the reactivation or receptionist case is missing.
