---
description: 'With no device, the QA runner records the mobile screenshots as not run with the boot command, and writes no waiver line.'
tags: [agent, qa, mobile]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:qa-runner agent with the brief below, then tell me what it recorded.

Brief: Feature 01 (docs/product/jobs/01-offline-notes, surface mobile-ui) is built. Run its test plan and record the results in qa-report.md, including the Evidence table for the kinds the plan lists. This environment has no shell, no emulator or simulator, and no device.
