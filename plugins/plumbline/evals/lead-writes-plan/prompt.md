---
description: The lead engineer writes a phase dev plan with clean ownership seams, AC-tagged tasks and docs-only product and qa rows, and leaves it in DRAFT for the user.
tags: [agent, lead]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:lead-engineer agent with the brief below, then tell me what it planned.

Brief: The phase 01 product docs and ux.md in docs/product/clinic/phases/phase-01 are approved. The app is a Node API in apps/api and a web front end in apps/web. Write dev-plan.md for phase 01. Don't spawn a team or start the build; just write the plan.
