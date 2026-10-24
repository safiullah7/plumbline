---
description: Triage sizes a small backend bug fix as Quick - no UX, one engineer, no feature folder.
tags: [skill, build, triage]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Two rooms in the same clinic can end up with the same name, like "Room 4" and "room 4". Reject the second one with a 409 and the message "A room with this name already exists". It is a bug in the rooms API; no screens change.

Stop as soon as you have shown the triage block and the criteria. Don't create files or start the work, and don't ask me anything first.
