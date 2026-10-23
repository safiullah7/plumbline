---
description: The code reviewer catches a tenant-isolation leak in a diff and rates it Critical with a concrete fix.
tags: [agent, reviewer]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
---

Dispatch the plumbline:code-reviewer agent with the brief below, then give me its findings.

Brief: Review eng-api's uncommitted change for phase 01 (docs/product/clinic/phases/phase-01). Git isn't available in this environment, so the diff is saved in changes.diff at the repo root; the changed file is apps/api/rooms/store.js.
