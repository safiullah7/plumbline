---
description: 'The code reviewer, told Security lens with the attack plan rows, the tenancy signal and its catalogue rows, marks the SEC test that asserts nothing real as a mismatch and names the catalogue item the plan has neither a row nor a Skipped line for.'
tags: [agent, reviewer, security]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
---

Dispatch the plumbline:code-reviewer agent with the brief below, then give me its findings and its SEC table exactly as it returned them.

Brief: Security lens. Review eng-api's uncommitted change for phase 01 (docs/product/clinic/phases/phase-01): a read of one room by its id. Git isn't available in this environment, so the diff is saved in changes.diff at the repo root; the changed files are apps/api/rooms/store.js, apps/api/rooms/routes.js and the new apps/api/test/attack/rooms.attack.test.js.

The workstream's SEC IDs and their attack plan rows:
| SEC ID | Surface | Attack | Must happen |
| --- | --- | --- | --- |
| SEC-01-001 | api | Staff of clinic B calls GET /api/rooms/<id of a room of clinic A> with a valid session | 404 { error: 'not found' } and nothing of the room in the body |
| SEC-01-002 | api | An admin of clinic A calls POST /api/rooms with a clinicId of clinic B in the body | the room is created in clinic A, none in clinic B |
| SEC-01-003 | api | A receptionist of clinic A calls POST /api/rooms with a valid session | 403 { error: 'forbidden' } and no room is created |
Signals: tenancy, authorization
Skipped: "write with another tenant's foreign key": rooms take no client-supplied foreign keys; "the same action across two tenants in one request": the API has no batch endpoint

The catalogue rows for those signals:
| Signal | Attacks |
| --- | --- |
| Authorization, tenancy | read another tenant's record by its ID; list without the tenant filter (count or page leak); write with another tenant's foreign key; tenant or role taken from the body or query instead of the session; the admin path with a staff token; the same action across two tenants in one request |
