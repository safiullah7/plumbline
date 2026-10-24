---
description: Build runs a Quick change with no shell - the lead is dispatched, the test is named after the criterion ID, and no feature folder is created.
tags: [skill, build, quick]
model: sonnet
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Two rooms in the same clinic can end up with the same name, like "Room 4" and "room 4". Reject the second one with a 409 and the message "A room with this name already exists". It is a bug in the rooms API; no screens change. Put the test in apps/api/rooms/rooms.test.js.

There is no shell in this environment, so nothing can be run. Don't ask me anything; go ahead.
