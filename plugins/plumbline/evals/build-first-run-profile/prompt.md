---
description: 'On a first /plumbline:build with no project profile, the skill proposes the surfaces it reads from the manifests, asks to use, edit or skip them, and does not start the work or write project.md before the answer.'
tags: [skill, build, profile, cli]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add a --quiet flag to `relnotes generate` that suppresses the "unknown tag" message on stderr and still exits with code 2.
