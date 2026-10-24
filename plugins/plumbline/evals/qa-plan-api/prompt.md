---
description: 'The QA engineer plans an api feature with contract, authz and negative cases per endpoint and recorded transcripts, and no browser checks.'
tags: [agent, qa, api]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:qa-engineer agent with the brief below, then tell me what it wrote.

Brief: Feature 01 (docs/product/invoices/01-void-invoices) is about to be built; no code for it exists yet. Its surface is api. Write test-plan.md for it.
