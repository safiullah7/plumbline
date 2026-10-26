---
description: "Triage keeps a routine change on Sonnet: only the lead runs on Opus."
tags: [skill, build, triage, models]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build In the rooms list, let users sort rooms by name, A to Z or Z to A, with A to Z as the default.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
