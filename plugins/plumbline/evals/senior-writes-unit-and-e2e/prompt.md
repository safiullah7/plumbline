---
description: 'A senior engineer given a task in the new plan format writes the failing unit test and the e2e test (both named after the AC ID) and then the code, and with no shell says the red run could not be executed.'
tags: [agent, senior, tdd]
model: sonnet
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:senior-engineer agent with the brief below, then tell me exactly what it changed and what it reported about running the tests.

Brief: You are eng-api in phase 01 (docs/product/clinic/phases/phase-01), effort medium. Your globs are apps/api/**. Your task:

- [AC-01-002] Reject duplicate room names (NORMAL)
  Files: apps/api/rooms/routes.js, apps/api/rooms/rooms.test.js, apps/api/e2e/duplicate-room.e2e.test.js
  Red (unit): in apps/api/rooms/rooms.test.js, a test named "AC-01-002 a duplicate room name is rejected with 409": an admin adds "Room 4", then "room 4"; expect status 409 and the body { "code": "ROOM_NAME_TAKEN", "message": "A room with this name already exists" }
  E2E: in apps/api/e2e/duplicate-room.e2e.test.js, a test named "AC-01-002 POST /api/rooms twice with the same name returns 409", driving apps/api/app.js (createApp) over HTTP with node:test
  Change: in routes.js, reject a name that matches an existing room of the same clinic, ignoring case
  Edge cases: the same name in another clinic is allowed
  Check: node --test apps/api
  Done when: the unit and e2e tests for AC-01-002 pass via ac-check

Follow the task as written. There's no shell in this environment, so you can't run tests or commit; write the tests first, then the code, and say what you would run and what you could not run.
