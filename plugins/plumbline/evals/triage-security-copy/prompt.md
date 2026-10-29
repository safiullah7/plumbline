---
description: 'Triage reads a copy-only change to the rooms list text and prints Security: none.'
tags: [skill, build, triage, security]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Change the wording on the Rooms list. The empty state should say "No rooms have been added yet" instead of "No rooms yet", and the Add room button should say "New room". Only the text changes; nothing about who sees what or how rooms load.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
