---
description: 'Triage of a pipeline-only change names the data surface, no UX, and sample-run evidence.'
tags: [skill, build, triage, surfaces, data]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build In the rollup pipeline, a sales row whose store_id is not in data/stores.csv should be set aside like the other bad rows and counted in the log line, instead of being totalled under an unknown store. It is a change to the pipeline code only; nothing a user sees changes.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
