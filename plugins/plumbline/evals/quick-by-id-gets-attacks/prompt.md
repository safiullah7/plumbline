---
description: 'A Quick by-id lookup in a multi-tenant project gets attack rows: the lead is dispatched, a SEC ID of the Quick form appears in the dispatch or the tests, an attack test is written, and no feature folder is created.'
tags: [skill, build, quick, security]
model: sonnet
max_turns: 40
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add a way to fetch one room by its id in the rooms API: export getRoom(req, res) from apps/api/rooms/routes.js. It reads the id from req.params.id and answers with the room as JSON, or with 404 and { error: 'not found' } when there is no such room. Add a lookup to apps/api/rooms/store.js if you need one, and put the tests in apps/api/rooms/rooms.test.js.

There is no shell in this environment, so nothing can be run. Don't ask me anything; go ahead.
