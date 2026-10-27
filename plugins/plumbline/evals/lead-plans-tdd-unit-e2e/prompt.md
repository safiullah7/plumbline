---
description: The lead engineer plans per engineer in the TDD task format with unit and e2e tests named after AC IDs, rates every task, sets each engineer's Effort, and writes no code.
tags: [agent, lead, tdd]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:lead-engineer agent with the brief below, then tell me what it planned.

Brief: The phase 01 product docs and ux.md in docs/product/clinic/phases/phase-01 are approved. The app is a Node API in apps/api and a web front end in apps/web; the project profile is docs/product/project.md. Write dev-plan.md for phase 01. Don't spawn a team, don't dispatch engineers and don't start the build; just write the plan.
