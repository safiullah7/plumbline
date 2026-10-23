---
description: The UX engineer explores design directions for a key screen and builds a self-contained prototype that matches ux.md.
tags: [agent, ux]
model: sonnet
max_turns: 15
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:ux-engineer agent with the brief below, then tell me what it produced.

Brief: Phase 01 (docs/product/clinic/phases/phase-01) needs the Rooms list screen designed properly before the build. Propose design directions for it in ux.md with a recommendation, and build the recommended direction as prototypes/rooms-list.html inside the phase folder, showing every state ux.md lists. There's no browser available in this environment, so skip the screenshot step.
