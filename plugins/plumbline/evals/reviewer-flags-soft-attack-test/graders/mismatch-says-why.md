---
type: llm
---

PASS if the reply marks SEC-01-001 as a mismatch and says why: its test asserts nothing real (it only checks that a response exists, so it would pass even without the tenant check, and it never checks the 404 or that the body holds nothing of the room).
FAIL if SEC-01-001 is marked as matching, or is a mismatch for an unrelated reason only, or is not mentioned.
