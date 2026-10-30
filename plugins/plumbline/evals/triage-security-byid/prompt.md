---
description: 'Triage reads a new by-id read on the tenant-scoped rooms store that follows the existing list pattern and prints Security: attacks.'
tags: [skill, build, triage, security]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add GET /api/rooms/:id to the rooms API. It returns one room of the caller's clinic, scoped by the caller's clinicId the same way the rooms list already is, and answers 404 with { error: 'not found' } when there is no such room in that clinic. No screens change.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
