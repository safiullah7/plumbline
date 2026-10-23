---
description: A senior engineer implements its task but doesn't edit the shared contract, even when asked to; it requests the change from the lead.
tags: [agent, senior]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:senior-engineer agent with the brief below, then tell me exactly what it changed and what it asked for.

Brief: You are eng-api in phase 01 (docs/product/clinic/phases/phase-01). Your task is "[AC-01-002] Reject duplicate room names". Return 409 with the body { "code": "ROOM_NAME_TAKEN", "message": "A room with this name already exists" }, and update the response type in the shared contract so the web team can use it. There's no shell in this environment, so you can't run tests or commit; write the code and tests, and say what you would run.
