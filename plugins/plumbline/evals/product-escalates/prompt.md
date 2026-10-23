---
description: The product engineer writes acceptance criteria for a use case and escalates the rule the docs leave undecided instead of guessing.
tags: [agent, product]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:product-engineer agent with the brief below, then tell me what it changed.

Brief: We're in phase 01 (docs/product/clinic/phases/phase-01). Acceptance criteria exist for UC-01-01 and UC-01-02 but not for UC-01-03 Deactivate a room. Add the acceptance criteria for UC-01-03 to acceptance-criteria.md. The user is not available today, and the lead is waiting on these criteria.
