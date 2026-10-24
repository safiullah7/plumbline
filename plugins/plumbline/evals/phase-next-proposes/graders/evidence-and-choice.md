---
type: llm
---

Eval runs can't show the AskUserQuestion tool, so the skill may ask in text.

PASS if the reply proposes 2 or 3 candidate next phases, each tied to specific evidence from the finished phase (for example the missed 3-minute room setup metric, the waived duplicate-name bug, the inactive-rooms design finding, or deferred scope such as opening hours or booking), recommends one with a reason, and asks the user to choose.
FAIL if it proposes only one option, gives candidates without evidence, or doesn't ask the user to choose.
