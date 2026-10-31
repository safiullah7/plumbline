---
description: The lead engineer plans a UI workstream that calls an API still to be built against the contract with a mock, ends it with a switch-to-the-real-API task blocked by the API task, and keeps the plan to 12 tasks.
tags: [agent, lead, v0.6]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:lead-engineer agent with the brief below, then tell me what it planned.

Brief: The phase 01 product docs and ux.md in docs/product/clinic/phases/phase-01 are approved. The app is a Node API in apps/api and a web front end in apps/web; the project profile is docs/product/project.md. Neither the rooms API nor the rooms UI exists yet: the API is built by one engineer and the web UI, which calls that API, by another, both starting from the approved docs and the contract in contracts/rooms.ts. Write dev-plan.md for phase 01. Don't spawn a team, don't dispatch engineers and don't start the build; just write the plan.
