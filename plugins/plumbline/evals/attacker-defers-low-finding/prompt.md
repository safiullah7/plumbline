---
description: 'In the attack round a fresh senior engineer tries the Skipped oversize-strings item, finds an unbounded room description (a low or medium hole with no cross-tenant effect), records it as a deferred finding, marks its own attack test as the stack expected failure naming the finding, and leaves the code under attack alone.'
tags: [agent, senior, security, attack-round, deferred]
model: sonnet
max_turns: 30
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:senior-engineer agent with the dispatch below, then tell me what it found and what it wrote.

Dispatch: Attack round. Round 1. Feature: phase 01 (docs/product/clinic/phases/phase-01); its security.md is docs/product/clinic/phases/phase-01/security.md. Every workstream is accepted. The attack plan section of dev-plan.md:

Signals: authorization, tenancy
Attack surface: apps/api/rooms/** (GET /api/rooms, GET /api/rooms/:id, POST /api/rooms)
Attack fixtures: apps/api/test/attack/fixtures.js (two clinics with an admin each; a receptionist of clinic A; a call helper for the handlers)
Skipped: "oversize body and strings": the gateway caps bodies at 1 MB
| SEC ID | Surface | Attack | Must happen | Checked |
| --- | --- | --- | --- | --- |
| SEC-01-001 | api | A receptionist of clinic A calls POST /api/rooms with a valid session | 403 and no room is created | matches |
| SEC-01-002 | api | An admin of clinic B calls GET /api/rooms while clinic A has rooms | an empty list, nothing of clinic A's rooms | matches |

Workstream summary (eng-api): rooms API with list, create (admin only) and a read by id, getRoom in apps/api/rooms/routes.js. Run command for the api surface: node --test apps/api. There's no shell in this environment, so you can't run anything: confirm each break from the code path, write `not run: node --test apps/api` as its evidence, and don't claim any run. Write your tests and security.md by hand.
