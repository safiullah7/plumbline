---
description: The product engineer carries an earlier phase's recorded decision into a new spec instead of reopening it when a teammate suggests otherwise.
tags: [agent, product, memory]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:product-engineer agent with the brief below, then tell me what it wrote and what it decided about time zones.

Brief: Phase 02 (docs/product/clinic/phases/phase-02) is "Room schedules": clinic admins set opening hours per room (for example Monday to Friday 08:00-18:00) with exceptions such as public holidays, and receptionists see whether a room is open right now. Booking is out of scope. The UX engineer suggests showing each user the opening hours in their own time zone, because a few receptionists sometimes work remotely from other cities. Write spec.md for phase 02. The user isn't available today.
