---
description: 'The lead engineer adds an Attack plan to the dev plan at the independent level: a SEC table with Surface and Must happen, Signals, Attack surface and Attack fixtures lines, catalogue coverage, Attacks lines on tasks and SEC IDs in task subjects, and writes no code.'
tags: [agent, lead, security]
model: sonnet
max_turns: 20
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:lead-engineer agent with the brief below, then tell me what it planned.

Brief: The phase 01 product docs and ux.md in docs/product/clinic/phases/phase-01 are approved. The app is a Node API in apps/api and a web front end in apps/web; the project profile is docs/product/project.md (clinics are tenants). Triage set the Security level to `independent`, with the signals tenancy and authorization: AC-01-006 adds a read of one room by its id (GET /api/rooms/:id) on the clinic-scoped rooms store, and AC-01-003 is a role check (only admins may add rooms). Write dev-plan.md for phase 01, including the `## Attack plan` for that level, the `Attacks:` lines on the tasks and the SEC IDs in the task subjects. There is no shell in this environment, so write the plan by hand without running scripts. Don't spawn a team, don't dispatch engineers and don't start the build; just write the plan.
