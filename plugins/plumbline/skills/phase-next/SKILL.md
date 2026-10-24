---
name: phase-next
description: Propose the next phase from evidence - unmet success metrics, shipped bugs, open findings, deferred scope - and update the roadmap once the user chooses.
disable-model-invocation: true
---
Use this after a phase is signed off, to choose what to build next from what
the product actually learned rather than from instinct.

1. Gather the evidence: run `bash <plugin>/scripts/phase-evidence.sh`, where
   <plugin> is the folder two levels above this SKILL.md. It lists, for every
   phase of the area, unmet success metrics, bugs shipped or waived, open
   findings, Non-Goals and blockers. If you can't run it, read each phase's
   signoff.md, qa-report.md, spec.md and progress.md for the same things.
2. Read the area's vision.md (who it's for, the problem, the Phases table) and
   decisions.md (what's settled and must not be reopened).
3. Propose 2-3 candidate next phases. For each: the outcome it changes for a
   user (measurable), the evidence behind it (cite the metric, bug, finding or
   Non-Goal by name), what it would include and leave out, and a rough size
   (S, M or L). Recommend one and say why it beats the others now.
4. Ask the user to choose, with AskUserQuestion when it's available, otherwise in
   plain text. Don't edit anything before they answer.
5. After they choose, update vision.md's Phases table: mark the finished phase
   done, and add or update the chosen phase's row with its Goal, Outcome, Why
   next and Status "Next". Then suggest `/plumbline:kickoff <area> <phase-id>`.
