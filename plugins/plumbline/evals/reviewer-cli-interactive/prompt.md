---
description: 'The code reviewer flags a new interactive prompt on a path that also runs non-interactively (CI, piped input, --json) as Critical.'
tags: [agent, reviewer, cli]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
---

Dispatch the plumbline:code-reviewer agent with the brief below, then give me its findings.

Brief: Review the uncommitted change to the relnotes CLI (module relnotes, feature 01-generate-notes), surface cli. Git isn't available in this environment, so the diff is saved in changes.diff at the repo root; the changed file is relnotes/cli.py.
