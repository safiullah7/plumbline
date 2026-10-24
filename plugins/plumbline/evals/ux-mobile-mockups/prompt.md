---
description: 'The UX engineer designs a mobile-ui screen with 390x844 and 430x932 mockups, platform conventions and an accessibility checklist, and plans no axe scan or capture.mjs.'
tags: [agent, ux, mobile]
model: sonnet
max_turns: 25
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:ux-engineer agent with the brief below, then tell me what it produced.

Brief: Feature 01 (docs/product/jobs/01-offline-notes, surface mobile-ui) needs the Job screen's Notes section designed before the build: adding a note, the "Not sent yet" badge, the offline state and the camera permission hint. Keep it compact. Write ux.md for this one section (screen inventory, the states, platform notes, the accessibility checklist you will plan, and your recommended direction), and build that direction as prototypes/job-notes.html inside the feature folder, showing every state ux.md lists. Don't rewrite design-principles.md or tokens.css. There's no browser or shell in this environment, so skip any screenshot step.
