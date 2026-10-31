---
type: llm
---

The brief held two ready tasks, A1 (AC-01-002, duplicate room names) and A2 (AC-01-006, the 50-room limit). There is no shell here, so no test could be run; that is expected and is not what you are judging.

PASS if the report shows that both tasks were worked in this one run: it names both A1 (AC-01-002) and A2 (AC-01-006) as done (tests written and code changed), with no promise of work still to come.
FAIL if the run stops after task 1 and says it will start, or is about to start, task 2 (for example "starting A2 next", "next up is AC-01-006" or "I'll continue with the limit rule"), or if the report covers only one of the two tasks.
