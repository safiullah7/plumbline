---
name: build
description: Start any piece of work - size the request as Quick, Standard or Full, show the decision, then run the matching process through to a PR.
disable-model-invocation: true
argument-hint: <request, e.g. "fix the double-booking check in rooms">
---
Arguments: the request, in the user's words.

You run in the main session, the only place that can ask the user anything:
subagents can't. <plugin> is the folder two levels above this SKILL.md. When a
step says "ask", use AskUserQuestion with your recommended option first; if
that tool isn't available, ask in plain text and end your turn until they reply.
Run every dispatch in the foreground and wait for its result before the next
step. If the user chooses to stop at any point, run step 8's cleanup and stop.

1. **Settings.**
   - Confirm mode: the `Confirm:` line of docs/product/project.md if that file
     exists (`auto` or `always`); else, if you have a shell, the
     PLUMBLINE_CONFIRM environment variable; else `auto`.
   - Teams: available if and only if the TeamCreate tool is in your tool list.
   - Shell: available if you have the Bash tool. Without it, see step 9.
   - Quick marker: if `.claude/plumbline-quick` exists, an earlier Quick change
     was interrupted or is still running in another session. Ask: still
     running (stop here), or clear it (delete the file and go on).
2. **Triage.** Dispatch the plumbline:product-engineer agent with model sonnet
   and this brief: "Triage mode. Request (verbatim): <request>. Today:
   <YYYY-MM-DD>. TeamCreate available: <yes|no>. Write no files. Return the
   fixed triage block; for Quick, 1-3 observable criteria with IDs
   AC-<yymmdd>-<nn>; and any question you couldn't decide."
3. **Show and ask.** Print the block exactly as returned, in this shape:

   ```
   Plumbline triage
   Size: Quick | Standard | Full
   Module: <name> (existing | new)
   Folder: none | docs/product/<module>/<nn>-<feature-slug>/
   UX: yes | no
   Engineers: <n>
   Docs: none | slim | full
   Team: no | yes
   Why: <one line>
   ```

   Then list the Quick criteria, if any. Ask only when one of these holds:
   - the request is too vague for observable criteria (ask what's missing);
   - triage couldn't decide the size or the module;
   - the size is Full (confirm the commitment, and that teams are on);
   - Confirm is `always` (confirm the block as a whole).
   Otherwise go straight on. If an answer changes the module, size or
   criteria, re-run step 2 with the answers added and print the new block.
   Never start Full work without the user's yes. If the size is Full and teams
   aren't available, stop: say Full needs an agent team and print the launch
   command `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude`.
4. **Preflight** (every size, before any branch or file).
   1. Run `git status --porcelain`. If the tree isn't clean, ask: stash
      (`git stash push -u`), continue on top, or stop.
   2. Tell the user, in one short list, the commands the agents will run:
      `git checkout -b`, `git add`, `git commit`, `git push`, `gh pr create`,
      `bash <plugin>/scripts/ac-check.sh`, and the test commands
      (PLUMBLINE_TYPECHECK, PLUMBLINE_LINT and PLUMBLINE_TEST_AC if set, else
      `npm run -s typecheck`, `npm run -s lint`, `npm run -s test:ac`). Say that
      Claude Code will ask them to approve any it doesn't already allow, and
      that a denied command stops the change. This is information, not a
      question: go on. Never edit permission settings yourself.
5. **Quick.**
   1. Create and switch to the branch `quick/<yymmdd>-<slug>` (slug: 2-4 words
      from the request) from the default branch's latest commit (`git fetch`
      first when there's a remote). Then write `.claude/plumbline-quick` with
      two lines: `branch=<branch>` and `ids=<IDs separated by spaces>`.
   2. Dispatch plumbline:lead-engineer with: "Quick mode. Request: <request>.
      Module: <module>. Criteria: <IDs and text>. Branch: <branch> (created;
      you're on it). Scripts: <plugin>/scripts." The lead dispatches one senior
      engineer, runs `ac-check.sh`, gets a review, pushes and opens the PR; it
      never creates a folder or merges. If it reports the work outgrew Quick,
      go back to step 2 with its reasons.
   3. Wrap-up, also after a failure or a cancel: delete `.claude/plumbline-quick`
      and report the PR link (or the compare URL), the `ac-check.sh` result,
      and the reviewer's findings and how each was resolved.
6. **Standard.**
   1. From the default branch, run
      `bash <plugin>/scripts/kickoff.sh <module> <feature-slug> --profile standard --ux`
      (or `--no-ux` when the block says `UX: no`). Its last line is the feature
      folder; use that path from now on, and say so if it differs from the
      block's. Then create and switch to the branch `feature/<nn>-<feature-slug>`,
      with <nn> from the printed folder, and commit the new docs by path.
   2. Dispatch plumbline:product-engineer: write the slim spec.md and
      acceptance-criteria.md for the request in the folder. Then dispatch,
      together: plumbline:qa-engineer with model sonnet to write test-plan.md
      (one Traceability row per AC with Status `planned`, and the Evidence
      lines), and, if `UX: yes`, plumbline:ux-engineer for ux.md and one mockup
      per key screen.
   3. Dispatch plumbline:lead-engineer to write dev-plan.md (Status: DRAFT,
      1-2 engineers). Show its summary and ask one question: approve the plan,
      or change it (say what). Relay changes to the lead until approved.
   4. Tell the lead the plan is approved: it sets READY, runs make-briefs.sh and
      builds, dispatching the engineers and a reviewer per workstream as
      subagents. With 2 engineers and teams available, create the team yourself
      with TeamCreate instead, spawning the lead and each engineer (pointed at
      its brief) as teammates. When every workstream is reviewed and the full
      suite passes, the lead ticks "Integration review" in signoff.md.
   5. Verify. Dispatch plumbline:qa-runner with: "Standard: run test-plan.md,
      record results in qa-report.md, set each Traceability Status in
      test-plan.md to pass or fail, run qa-summary.sh, set the Verdict and tick
      the QA verdict box." Dispatch plumbline:product-engineer to walk the
      finished journeys against the criteria (Journey results, Product
      findings, Success metrics results in signoff.md) and tick Product
      verification; with `UX: yes`, plumbline:ux-engineer checks each screen
      against ux.md and ticks Design verification. Then follow
      /plumbline:signoff (<plugin>/skills/signoff/SKILL.md): gap check, full
      suite, push, PR. If the gap check lists gaps, send each to its owner and
      run it again.
7. **Full.** Requires teams (step 3). Run
   `bash <plugin>/scripts/kickoff.sh <module> <feature-slug> --profile full --ux`
   (or `--no-ux`), adding `--new-module` when the block says the module is new,
   then create the branch from the printed folder as in 6.1. For a new module,
   product writes vision.md first. Then the full flow:
   discovery (follow <plugin>/skills/discover/SKILL.md yourself, since it asks
   the user) → spec, ux.md and prototypes (UX), test plan (QA engineer) →
   lead's plan → the user approves → READY and make-briefs.sh → team build
   (TeamCreate; teammates from the plan's Team table) → QA runner → signoff as
   in 6.5.
8. **Questions, waivers and cleanup** (any size).
   - When an agent returns a question only the user can answer, ask it, then
     pass the answer back to that agent.
   - Agents can't write `Evidence waived:` or `Accessibility waived:` lines;
     the ownership guard blocks them. When an agent or the gap check reports
     evidence or accessibility results that can't be produced, ask the user:
     waive it (with the reason) or get it done. Only after an explicit yes,
     add the line yourself to the feature's qa-report.md, on its own line:
     `Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)` or
     `Accessibility waived: <reason> (approved by <name>)`, where <name> is
     the user's name (`git config user.name`, else ask).
   - Cleanup on stop: delete `.claude/plumbline-quick` if you wrote it.
9. **No shell** (e.g. eval runs). Do steps 1-3 as usual. Then:
   - Quick: skip step 4, the branch and the marker. Dispatch the lead as in 5.2, adding
     "No shell: no branch, commits, checks or PR. Quick change: no feature
     folder; don't write phase docs. Write the tests, named after the IDs, and
     the code." Report that the change is uncommitted and unchecked, and the
     commands to run once a shell is available.
   - Standard or Full: create the feature folder by hand, as the hand fallback
     in <plugin>/skills/kickoff/SKILL.md describes, then stop: building needs
     a shell for git and the tests.
