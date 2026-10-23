---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-02/spec.md }
---

PASS if the spec states concrete business rules for opening hours (time granularity or format, invalid or overlapping ranges, how exceptions such as holidays override the weekly hours), says who can edit and who can only view, keeps schedules scoped to the clinic, and states that booking is out of scope.
FAIL if the rules are vague, or permissions, clinic scoping or the booking exclusion are missing.
