---
description: 'Triage reads a request that adds staff sign-in and roles to a multi-tenant project and prints Security: independent, with a size above Quick.'
tags: [skill, build, triage, security]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add staff sign-in to the clinic app. Staff sign in with an email and a password, and a session cookie keeps them signed in for 8 hours. Each staff member has a role, admin or receptionist, and only admins may add or deactivate rooms; receptionists can only view them. Staff only ever see their own clinic's data.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
