---
type: llm
---

PASS if the reply says the phase can't be signed off yet, lists the gaps (an AC without a test case, the QA verdict not being PASS, an open question, unticked sign-off boxes), and does not claim to have run the test suite, pushed, or opened a PR.
FAIL if it signs the phase off, claims a PR was opened, or misses the untested AC or the pending verdict.
