---
description: 'The QA engineer checks the built feature from its journeys and criteria, fills the Traceability rows, records not run honestly when it has no browser or shell, and does no scan, no code and no waiver.'
tags: [agent, qa]
model: sonnet
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:qa-engineer agent with the brief below, then tell me what it recorded and what it could not run.

Brief: Feature 01 (docs/product/rooms/01-room-management, a Standard feature) of the rooms module has just been built. Check that each journey in ux.md and each acceptance criterion works, and record the results in test-plan.md and qa-report.md. There is no shell, no browser and no running app in this environment, and no URL is given. Don't ask the user anything.
