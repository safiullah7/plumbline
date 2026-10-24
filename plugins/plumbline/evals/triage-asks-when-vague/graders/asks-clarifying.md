---
type: llm
---

Eval runs can't show the AskUserQuestion tool, so the skill may ask in text. Judge the reply.

PASS if the reply says the request is too vague, or what is missing, and asks the user at least one clarifying question about what they want changed in rooms (for example which behaviour, which users, or what outcome), then waits for the answer.
FAIL if it picks a meaning for "better" and goes ahead, presents a finished plan or criteria as if the request were clear, or asks nothing.
