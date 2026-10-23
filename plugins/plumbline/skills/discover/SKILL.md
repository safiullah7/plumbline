---
name: discover
description: Interview the user about a phase before writing anything, then draft spec.md from their answers.
disable-model-invocation: true
---
Arguments: optional one-line idea for the phase.

You are running product discovery for the phase in .claude/current-phase. Ask
before you write: the spec is only as good as the answers behind it.

1. Read the area's vision.md and decisions.md, the phase's spec.md template, and
   the previous phase's signoff.md and questions.md if they exist. Skim the code
   for the area. Note what's already decided so you don't ask it again.
2. Interview the user with AskUserQuestion, a few questions per round, offering
   concrete options with your recommendation first. Cover, in order:
   - who uses this, in what situation, and what they're trying to get done
   - what "done" looks like for them, and how we'd measure it
   - the hard parts: edge cases, permissions, limits, failure and empty cases,
     what happens to existing data
   - what's out of scope for this phase
   Dig into vague answers ("it should be easy") until they are testable. Stop
   when another round wouldn't change the spec.
3. Draft spec.md from the template: Goal, What we learned, Users and roles, Use
   cases, Requirements (P0/P1/P2), Business rules, Data and permissions,
   Non-Goals, Success metrics, Decisions. Cite the user's answers in Decisions.
   Anything still undecided goes to questions.md as OPEN (or ESCALATED if it
   blocks a P0), never into the spec as a guess.
4. Show the user a short summary and the open questions, and suggest handing
   spec.md to the UX engineer next.
