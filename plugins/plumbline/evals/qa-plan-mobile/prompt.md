---
description: 'The QA engineer plans a mobile-ui feature with simulator or emulator screenshots, flow tests and a checklist, and no URL.'
tags: [agent, qa, mobile]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:qa-engineer agent with the brief below, then tell me what it wrote.

Brief: Feature 01 (docs/product/jobs/01-offline-notes) is about to be built; no code for it exists yet. Its surface is mobile-ui. Write test-plan.md for it.
