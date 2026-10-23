---
description: The QA engineer writes a test plan from the product docs before the build, tracing every case to an AC and covering negative, permission, tenant and UI-state cases.
tags: [agent, qa]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:qa-engineer agent with the brief below, then tell me what it wrote.

Brief: Phase 01 (docs/product/clinic/phases/phase-01) is about to be built; no code for it exists yet. Write test-plan.md for phase 01.
