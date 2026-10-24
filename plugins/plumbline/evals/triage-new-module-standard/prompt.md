---
description: Triage marks a module that has code but no docs folder as new, and sizes a single new screen in it as Standard.
tags: [skill, build, triage]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Add a new Patient search screen to the patients module, with its own page. A receptionist types part of a patient's name into a search box and sees the matching patients, each with name and phone. Searching happens on the server, so add a search endpoint to the patients API. With no match the screen says "No patients found".

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
