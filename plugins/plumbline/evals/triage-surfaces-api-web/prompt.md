---
description: 'Triage reads the project profile and names both surfaces, api and web-ui, for a change that adds an endpoint and a page, with evidence for each.'
tags: [skill, build, triage, surfaces]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add a Room details page to the rooms module. From the Rooms list a user clicks a room's name and sees its name, its description and an Active or Inactive badge, with a Back to rooms link. The page loads the room from a new endpoint, GET /api/rooms/:id, which answers 404 with { error: 'not found' } when the room doesn't exist in the caller's clinic; the page then says "Room not found".

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
