---
type: llm
---

Eval runs can't show the AskUserQuestion tool, so the skill may ask in text. Judge the questions in the reply.

PASS if the reply asks the user questions before writing the spec, covering who uses room schedules and what they need, and at least two hard parts specific to opening hours (for example overlapping or invalid ranges, holiday or repair exceptions, time zones, what "open now" means at a boundary, or who may edit), each with concrete options.
FAIL if it writes or presents a finished spec without asking, or its questions are generic ("any other requirements?") without concrete options.
