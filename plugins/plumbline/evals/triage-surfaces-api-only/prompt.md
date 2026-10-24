---
description: 'Triage of an API-only change names the api surface only, leaves UX out of the roles and says UX no.'
tags: [skill, build, triage, surfaces]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add GET /api/rooms/:id to the rooms API. It returns the room as JSON, or 404 with { error: 'not found' } when the room doesn't exist in the caller's clinic. It is an API addition only; no screens change.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
