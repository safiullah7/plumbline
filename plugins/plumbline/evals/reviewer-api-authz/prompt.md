---
description: 'The code reviewer rates a missing authorization check on an API endpoint as Critical and names the fix.'
tags: [agent, reviewer, api]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
---

Dispatch the plumbline:code-reviewer agent with the brief below, then give me its findings.

Brief: Review the uncommitted change for feature 01 (docs/product/invoices/01-void-invoices), surface api. Git isn't available in this environment, so the diff is saved in changes.diff at the repo root; the changed files are under services/api.
