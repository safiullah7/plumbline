---
type: llm
---

PASS if the report (or the order of the engineer's work) shows that the unit test and the e2e test were written before the change to routes.js, as the task's red-green order requires, and that the work stayed inside apps/api (contracts and other engineers' files untouched; a needed contract change is requested from the lead, not made).
FAIL if the code was written first and the tests after, only one of the two tests was written, or the engineer edited the shared contract or files outside apps/api.
