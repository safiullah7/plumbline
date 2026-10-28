---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
---

Judge only the engineers' workstreams. The product and qa rows share docs/product/** on purpose; ignore them. The shared contract (contracts/rooms.ts) already exists, so engineers may build against it.

PASS if no two engineers own overlapping globs, there are at most 4 engineers, and any contract or schema change the plan needs lands before the engineers' tasks start.
FAIL if two engineers own overlapping globs, there are more than 4 engineers, or a contract change is scheduled after or alongside the tasks that depend on it.
