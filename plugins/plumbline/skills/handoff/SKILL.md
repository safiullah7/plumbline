---
name: handoff
description: End a work session cleanly - record progress, commit the phase docs, and print the prompt to resume in a fresh session.
disable-model-invocation: true
---
Use this before ending a long session, so the next one starts from notes instead
of re-reading everything.

1. Read .claude/current-phase, then the phase's progress.md (create it from the
   kickoff template if it's missing).
2. Add an entry at the top of progress.md, dated, with four parts:
   - Done: what was finished this session, with AC IDs and commit hashes
   - Next: the next 1-3 concrete steps, with AC IDs and owners
   - Blockers: OPEN or ESCALATED questions and failing tests, by name
   - Resume prompt: one paragraph a fresh session can paste to continue
3. Commit only the phase docs folder, staging by path (git add <phase folder>).
   Never git add -A or git add . and never commit code here.
4. Print the resume prompt, and suggest starting a fresh session with it.
