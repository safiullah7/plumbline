You're running a full Plumbline phase end to end, as a benchmark. This session
was started in D:\Repos\plumbline-e2e (a tiny clinic app, see README.md and
docs/brief.md) with agent teams and the Plumbline plugin loaded. You are the
lead. Run the whole phase with a real team and don't skip steps; the point is to
see how well the plugin works and what it costs. Use bash for shell commands.
The user approves the dev plan in advance and is not available for questions:
everything they decided is in docs/brief.md.

1. Kickoff: read the plugin's skills/kickoff/SKILL.md and follow it for area
   "clinic", phase "phase-01", short name "rooms". If writing
   .claude/current-phase is refused, stop and say so.
2. Discovery and UI text: spawn product (agent type plumbline:product-engineer),
   named exactly product. Point it at docs/brief.md. Product writes spec.md,
   acceptance-criteria.md and ux.md (the journeys and a text description of each
   screen, including the Rooms list; no prototype). Questions the brief doesn't
   answer are decided as the brief says.
3. Plan: write dev-plan.md yourself, following the lead engineer's rules, with
   two engineers named eng-api (apps/api/**) and eng-web (apps/web/**). Plan per
   engineer: the failing unit test first, the e2e test, a done-when, and an
   Effort in the Team table. Keep the product and qa rows. Then set
   "Status: READY" (pre-approved).
   If the plugin has scripts/make-briefs.sh, run it.
4. Build: spawn eng-api and eng-web (agent type plumbline:senior-engineer, model
   sonnet, the effort from the plan). They work test-first and write unit and e2e
   tests. Create their tasks in the task list, every subject starting with its AC IDs.
   Wait for them to finish. Review each workstream with the
   plumbline:code-reviewer subagent and have the owners fix Critical findings.
5. QA: spawn plumbline:qa-engineer, named qa. It tests that each journey and
   criterion works and fills test-plan.md and qa-report.md. No browser may be
   available; if so, test through the API and the HTML, and say which browser
   checks were skipped. Have bugs fixed and re-tested. qa sets the verdict.
6. Verify and sign off: product records its verification in signoff.md. Then run the plugin's scripts/signoff-check.sh if it exists, or
   follow skills/signoff/SKILL.md's checks by hand. Don't push or open a PR.
7. Shut the team down, then report:
   - a table: AC ID, test name, passing (run `npm run test:ac -- "<all IDs>"`
     and `npm test`)
   - OPEN and ESCALATED questions left, QA verdict, open bugs by severity
   - anything in the plugin that got in the way or was missing
   Save the report to D:\Repos\plumbline-e2e\e2e-report.md, written last.
