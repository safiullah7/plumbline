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
2. Discovery and design, as a team: spawn product (agent type
   plumbline:product-engineer), design (plumbline:ux-engineer) and qa
   (plumbline:qa-engineer), named exactly product, design and qa. Point them at
   docs/brief.md. Product writes spec.md and acceptance-criteria.md; design
   writes ux.md and one prototype (the Rooms list); qa writes test-plan.md.
   Questions the brief doesn't answer are decided as the brief says.
3. Plan: write dev-plan.md yourself, following the lead engineer's rules, with
   two engineers named eng-api (apps/api/**) and eng-web (apps/web/**). Keep the
   product, design and qa rows. Then set "Status: READY" (pre-approved).
   If the plugin has scripts/make-briefs.sh, run it.
4. Build: spawn eng-api and eng-web (agent type plumbline:senior-engineer).
   Create their tasks in the task list, every subject starting with its AC IDs.
   Wait for them to finish. Review each workstream with the
   plumbline:code-reviewer subagent and have the owners fix Critical findings.
5. QA: have qa run the test plan (spawn plumbline:qa-runner named qa-runner if
   the plugin has that agent). No browser may be available; if so, test through
   the API and the HTML, and say which browser checks were skipped. Have bugs
   fixed and re-tested. qa sets the verdict.
6. Verify and sign off: product and design record their verification in
   signoff.md. Then run the plugin's scripts/signoff-check.sh if it exists, or
   follow skills/signoff/SKILL.md's checks by hand. Don't push or open a PR.
7. Shut the team down, then report:
   - a table: AC ID, test name, passing (run `npm run test:ac -- "<all IDs>"`
     and `npm test`)
   - OPEN and ESCALATED questions left, QA verdict, open bugs by severity
   - anything in the plugin that got in the way or was missing
   Save the report to D:\Repos\plumbline-e2e\e2e-report.md, written last.
