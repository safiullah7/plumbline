---
description: "Triage puts the risky judgement on Opus: product and QA for refunds with role-based permissions; the lead stays on Opus."
tags: [skill, build, triage, models]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Let admins refund the deposit of a cancelled room booking, in full or in part. Receptionists can see refunds but can't issue them, and every refund is recorded with who issued it and when.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
