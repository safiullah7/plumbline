---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-01/test-plan.md }
---

PASS if every AC has at least one case in the traceability table, and the plan includes: negative cases (a duplicate name and an invalid name length), a permission case (a receptionist), a tenant-isolation case (two clinics), UI state cases (empty, loading and error), and at least two viewports.
FAIL if any of these is missing.
