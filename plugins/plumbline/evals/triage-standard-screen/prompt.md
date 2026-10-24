---
description: Triage sizes one new screen in an existing module as Standard, with UX and a feature folder in that module.
tags: [skill, build, triage]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add a Room details page to the rooms module. From the Rooms list, a user clicks a room's name and sees its name, its description and an Active or Inactive badge, with a Back to rooms link. If the room no longer exists, the page says "Room not found".

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
