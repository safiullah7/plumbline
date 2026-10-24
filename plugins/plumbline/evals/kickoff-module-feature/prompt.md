---
description: Kickoff in the module form creates the next feature folder in an existing module by hand, with the slim spec and the .plumbline file.
tags: [skill, kickoff]
model: sonnet
max_turns: 40
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

/plumbline:kickoff rooms room-schedules --profile standard

There is no shell in this environment, so use the hand fallback, skip the branch and commit steps and say you skipped them.
