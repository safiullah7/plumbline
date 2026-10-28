---
description: The product engineer writes ux.md as text only, with journeys, a screen inventory, and per screen the layout, every state and the exact copy, and creates no mockup files.
tags: [agent, product, ux]
model: sonnet
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Write, Edit]
---

Dispatch the plumbline:product-engineer agent with the brief below, then tell me what it wrote.

Brief: We're in phase 01 (docs/product/clinic/phases/phase-01). The spec and the acceptance criteria are written, but ux.md is still the empty template. Write ux.md for the phase: the engineers will build the UI from your text alone. Don't change spec.md or acceptance-criteria.md. The user isn't available today.
