---
description: 'A senior engineer given a brief with two ready tasks writes the tests and code for the first and then goes straight on to the second in the same run, without ending on an announcement of the next task.'
tags: [agent, senior, tdd, v0.6]
model: sonnet
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:senior-engineer agent with the brief below. When it comes back, tell me exactly what it changed, and quote its final message word for word.

Brief: You are eng-api in phase 01 (docs/product/clinic/phases/phase-01), effort medium. Your globs are apps/api/**. Your tasks, in the plan's order; both are ready now:

- [AC-01-002] A1: Reject duplicate room names (NORMAL)
  Files: apps/api/rooms/routes.js, apps/api/rooms/duplicate-room.test.js, apps/api/e2e/duplicate-room.e2e.test.js
  Red (unit): in apps/api/rooms/duplicate-room.test.js, a test named "AC-01-002 a duplicate room name is rejected with 409": an admin adds "Room 4", then "room 4"; expect status 409 and the body { "code": "ROOM_NAME_TAKEN", "message": "A room with this name already exists" }
  E2E: in apps/api/e2e/duplicate-room.e2e.test.js, a test named "AC-01-002 POST /api/rooms twice with the same name returns 409", driving apps/api/app.js (createApp) over HTTP with node:test
  Change: in routes.js, reject a name that matches an existing room of the same clinic, ignoring case
  Edge cases: the same name in another clinic is allowed
  Check: node --test apps/api
  Done when: the unit and e2e tests for AC-01-002 pass via ac-check
- [AC-01-006] A2: Limit a clinic to 50 rooms (NORMAL)
  Files: apps/api/rooms/routes.js, apps/api/rooms/room-limit.test.js, apps/api/e2e/room-limit.e2e.test.js
  Red (unit): in apps/api/rooms/room-limit.test.js, a test named "AC-01-006 the 51st room is rejected with 409": an admin adds 50 rooms, then a 51st; expect status 409 and the body { "code": "ROOM_LIMIT_REACHED", "message": "A clinic can have at most 50 rooms" }
  E2E: in apps/api/e2e/room-limit.e2e.test.js, a test named "AC-01-006 the 51st POST /api/rooms returns 409", driving apps/api/app.js (createApp) over HTTP with node:test
  Change: in routes.js, reject a new room when the clinic already has 50 rooms, active or inactive
  Edge cases: another clinic's rooms don't count toward the limit
  Check: node --test apps/api
  Done when: the unit and e2e tests for AC-01-006 pass via ac-check

Follow the tasks as written, red tests first. There's no shell in this environment, so you can't run tests, commit or claim tasks; say what you would run and what you could not run.
