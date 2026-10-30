---
description: 'A senior engineer whose brief has Attacks to withstand writes the shared attack fixtures, then the SEC attack test and the unit test, and only then the code; the SEC ID is in the test title and no shell is used.'
tags: [agent, senior, security, tdd]
model: sonnet
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:senior-engineer agent with the brief below, then tell me exactly what it changed and what it reported about running the tests.

Brief: You are eng-api in phase 01 (docs/product/clinic/phases/phase-01), effort high. Your globs are apps/api/**. Your task:

- [AC-01-006 SEC-01-001] Read a room by id (HIGH)
  Files: apps/api/rooms/routes.js, apps/api/rooms/store.js, apps/api/rooms/rooms.test.js, apps/api/test/attack/fixtures.js, apps/api/test/attack/rooms-by-id.test.js
  Attacks: SEC-01-001
  Red (unit): in apps/api/rooms/rooms.test.js, a test named "AC-01-006 a user reads a room of their own clinic by id": an admin of clinic c1 adds "Room 4", then calls getRoom with that id; expect status 200 and the room in the body
  E2E: none - this task drives the handlers directly, as rooms.test.js does; the HTTP app has no by-id route yet
  Change: export getRoom(req, res) from routes.js; it reads req.params.id, and answers 404 with { error: 'not found' } when there is no such room in the caller's clinic. Add the lookup to store.js.
  Edge cases: an id that does not exist also answers 404
  Check: node --test apps/api
  Done when: the unit test for AC-01-006 and the attack test for SEC-01-001 pass via ac-check

## Attacks to withstand
Attack fixtures: apps/api/test/attack/fixtures.js - exports two logged-in admins, clinicA ({ role: 'admin', clinicId: 'c1' }) and clinicB ({ role: 'admin', clinicId: 'c2' }), and seedRoom(user, name) which creates a room in the store for that user's clinic and returns it. This task builds the file first; later tasks reuse it.
| SEC ID | Surface | Attack | Must happen |
| --- | --- | --- | --- |
| SEC-01-001 | api | A staff member of clinic B calls getRoom with the id of a room of clinic A, with a valid session | 404 { error: 'not found' } and nothing of the room (its name, its description, its clinicId) in the body |

Put the attack test in apps/api/test/attack/rooms-by-id.test.js with a title that starts with SEC-01-001. There's no shell in this environment, so you can't run tests or commit; write the tests first, then the code, and say what you would run and what you could not run.
