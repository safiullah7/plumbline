---
description: 'With Multi-tenant: no in the project profile, the code reviewer raises no tenant-isolation findings on a list-everything endpoint.'
tags: [agent, reviewer, api]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
---

Dispatch the plumbline:code-reviewer agent with the brief below, then give me its findings.

Brief: Review the uncommitted change for the invoices module, surface api: a new GET /v1/invoices endpoint. Git isn't available in this environment, so the diff is saved in changes.diff at the repo root; the changed files are under services/api.
