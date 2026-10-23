---
description: The product engineer turns a short brief into a phase spec with clear rules, priorities, scope limits and success measures.
tags: [agent, product, capability]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:product-engineer agent with the brief below, then tell me what it wrote.

Brief: Phase 02 (docs/product/clinic/phases/phase-02) is "Room schedules". Clinic admins need to set opening hours for each room, for example Monday to Friday 08:00-18:00, and add exceptions such as public holidays or a day closed for repairs. Receptionists need to see at a glance whether a room is open right now. Booking appointments is still out of scope. Write spec.md for phase 02. The user has already answered everything they're going to answer, so work from this brief and the existing docs.
