---
description: 'The QA engineer plans an ai feature with an eval-set section that has a numeric pass threshold, plus injection cases, cost and latency budgets.'
tags: [agent, qa, ai]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:qa-engineer agent with the brief below, then tell me what it wrote.

Brief: Feature 01 (docs/product/assistant/01-ticket-summaries) is about to be built; no code for it exists yet. Its surface is ai. Write test-plan.md for it.
