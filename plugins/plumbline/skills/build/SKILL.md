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
step. Dispatch agents without a `name`, except where a step spawns teammates:
with agent teams on, a named agent joins the team as a teammate, and the hooks
then hold it to the dev plan's Ownership table. If the user chooses to stop at any point, run step 8's cleanup and stop.

1. **Settings.**
   - Shell: available if you have the Bash tool. Without it, see step 9.
   - Repo root: with a shell, if `git rev-parse --show-toplevel` isn't the
     folder this session started in, stop: say the hooks and the scripts would
     see different projects, and to start Claude Code in the repo root.
   - Teams: on when agent teams are enabled: with a shell, when
     `echo "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"` prints `1`; without one,
     when your Agent tool's description says a named agent joins this
     session's team, or a TeamCreate tool is listed (older Claude Code). Else off.
   - Quick marker: if `.claude/plumbline-quick` exists, an earlier Quick change
     was interrupted or is still running in another session. Ask: still
     running (stop here), or clear it (delete the file and go on).
   - Profile (ignore surface rows marked "(check)" until confirmed): if
     docs/product/project.md doesn't exist, show a proposal: with
     a shell, the output of `bash <plugin>/scripts/detect-project.sh`; without
     one (or if it fails), rows you propose from the manifests you can read
     (package.json, pyproject.toml, go.mod, pubspec.yaml, Cargo.toml), in the
     same Surfaces table. Ask once: use it as is, edit it (say what), or skip
     for now (no profile: the checks keep their defaults and triage proposes
     surfaces from the code). On use or edit, write the file yourself: drop
     "(check)" rows the user didn't keep and the mark on those kept, and set
     `Confirmed by: <name> on <YYYY-MM-DD>` (<name> as in step 8). Point out
     any surface whose AC tests cell is blank: its checks fail until it names
     a command (or `none`). A cell may join adapters with `+`: a web surface
     whose package has `@playwright/test` gets `node --dir <pkg> + playwright
     --dir <pkg>` (detect-project proposes it). If the user said not to ask
     anything, skip and say so.
   - Confirm mode: the `Confirm:` line of docs/product/project.md if that file
     exists (`auto` or `always`); else, if you have a shell, the
     PLUMBLINE_CONFIRM environment variable; else `auto`.
2. **Triage.** Dispatch the plumbline:product-engineer agent with model sonnet
   and this brief: "Triage mode. Request (verbatim): <request>. Today:
   <YYYY-MM-DD>. Agent teams on: <yes|no>. Profile: <docs/product/project.md,
   or: none (skipped by the user); propose surfaces from the code and don't
   ask about them>. Write no files. Return the
   fixed triage block; for Quick, 1-3 observable criteria with IDs
   AC-<yymmdd>-<nn>; and any question you couldn't decide."
3. **Show and ask.** Print the block exactly as returned, in this shape:

   ```
   Plumbline triage
   Size: Quick | Standard | Full
   Module: <name> (existing | new) | none
   Folder: none | docs/product/<module>/<nn>-<feature-slug>/
   Surfaces: <comma-separated>
   Roles: <e.g. product, lead, 2 engineers, reviewer, QA>
   Evidence: <one kind per surface, e.g. web-ui: journeys; api: transcripts>
   UX: yes | no
   Engineers: <n>
   Docs: none | slim | full
   Team: no | yes
   Why: <one line>
   ```

   The evidence kinds: web-ui and desktop-ui journeys, mobile-ui flow-tests,
   api transcripts, service job-tests, cli golden-output, library
   doc-examples, data sample-run, ai eval-set, infra plan-output.

   Then list the Quick criteria, if any. Ask only when one of these holds:
   - the request is too vague for observable criteria (ask what's missing);
   - triage couldn't decide the size or the module;
   - the size is Full (confirm the commitment, and that teams are on);
   - there's no project.md yet (step 1 asks this, once);
   - Confirm is `always` (confirm the block as a whole).
   Otherwise go straight on. If an answer changes the module, size, surfaces
   or criteria, re-run step 2 with the answers added and print the new block.
   From here on, dispatch only the roles the Roles line lists. `UX: yes`
   means the feature has UI: product writes ux.md. Give no model to the lead,
   or to product after triage: both run on opus. Engineers run on sonnet with
   the effort the lead sets; the reviewer's model is the lead's call.
   Never start Full work without the user's yes. If the size is Full and teams
   aren't available, stop: say Full needs an agent team and print the launch
   command `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude`.
4. **Preflight** (every size, before any branch or file).
   1. Run `git status --porcelain`. If the tree isn't clean (a project.md you
      wrote in step 1 doesn't count), ask: stash (`git stash push -u`, leaving
      that project.md out), continue on top, or stop.
   2. Tell the user, in one short list, the commands the agents will run:
      `git checkout -b`, `git add`, `git commit`, `git push`, `gh pr create`,
      `bash <plugin>/scripts/ac-check.sh`, and the test commands for each of
      the block's surfaces: PLUMBLINE_TYPECHECK, PLUMBLINE_LINT and
      PLUMBLINE_TEST_AC if set; else that surface's Typecheck, Lint and AC
      tests cells in project.md (an adapter name runs
      `<plugin>/scripts/ac-tests/<name>.sh`); else `npm run -s typecheck`,
      `npm run -s lint`, `npm run -s test:ac`; plus each surface's Run command
      (the dev server QA and the e2e tests use) and the browser tool QA drives.
      Say that
      Claude Code will ask them to approve any it doesn't already allow, and
      that a denied command stops the change. This is information, not a
      question: go on. Never edit permission settings yourself.
5. **Quick.**
   1. Create and switch to the branch `quick/<yymmdd>-<slug>` (slug: 2-4 words
      from the request) from the default branch's latest commit (`git fetch`
      first when there's a remote). Then write `.claude/plumbline-quick` with
      two lines: `branch=<branch>` and `ids=<IDs separated by spaces>`. Commit
      a project.md you wrote in step 1 by path.
   2. Dispatch plumbline:lead-engineer with: "Quick mode. Request: <request>.
      Module: <module>. Surface: <the block's one surface, or none without a
      profile>. Criteria: <IDs and
      text>. Branch: <branch> (created; you're on it). Scripts: <plugin>/scripts.
      Pick the engineer's effort by the work's complexity."
      The lead dispatches one senior engineer on sonnet, runs
      `ac-check.sh "<IDs>" --surface <surface>`, gets a review, pushes and
      opens the PR; it never creates a folder or merges. If it reports the
      work outgrew Quick, go back to step 2 with its reasons.
   3. Wrap-up, also after a failure or a cancel: delete `.claude/plumbline-quick`
      and report the PR link (or the compare URL), the `ac-check.sh` result,
      and the reviewer's findings and how each was resolved.
6. **Standard.**
   1. From the default branch, run
      `bash <plugin>/scripts/kickoff.sh <module> <feature-slug> --profile standard --ux --surfaces <s1,s2>`
      (`--no-ux` when the block says `UX: no`; <s1,s2> is the Surfaces line
      without spaces). Its last line is the feature folder; use that path from
      now on, and say so if it differs from the block's. Then create and switch to the branch `feature/<nn>-<feature-slug>`,
      with <nn> from the printed folder, and commit the new docs (and a
      project.md you wrote in step 1) by path.
   2. Dispatch plumbline:product-engineer: write the slim spec.md and
      acceptance-criteria.md for the request in the folder and, if `UX: yes`,
      ux.md: the journeys, the screen inventory and each screen in words
      (layout, components, every state, exact copy).
   3. Dispatch plumbline:lead-engineer to write dev-plan.md (Status: DRAFT,
      1-2 engineers): per engineer, ordered tasks with the failing unit test
      first, the e2e test and a done-when, and the Team table with each
      engineer's Effort. Show its summary and ask one question: approve the
      plan, or change it (say what). Relay changes to the lead until approved.
   4. Tell the lead the plan is approved: it sets READY, runs make-briefs.sh and
      builds, dispatching each engineer as a subagent on sonnet with that
      engineer's Effort, reviewing each workstream against the plan,
      dispatching a reviewer per workstream and checking each with
      `ac-check.sh "<its IDs>" --surface <its surface>`. With 2 engineers and
      teams on, spawn the team yourself instead: the lead and each engineer (pointed at its brief) as teammates,
      each with the Agent tool, its agent type and its name from the plan's Team
      table, each engineer with model sonnet and the effort in its Effort
      column (call TeamCreate first if your Claude Code has it). Teammates can't
      spawn teammates, so you spawn them all. When every workstream is reviewed and the full
      suite passes, the lead ticks "Integration review" in signoff.md.
   5. Verify. Dispatch plumbline:qa-engineer to test the flows (functional
      only) with: "Standard: check each journey and criterion works, fill
      test-plan.md Traceability, log bugs in qa-report.md, record the Evidence
      row for each surface's required kind, set the Verdict and tick the QA
      verdict box. Required evidence: <the block's Evidence line>." Dispatch
      plumbline:product-engineer to walk the finished journeys against the criteria (Journey results, Product
      findings, Success metrics results in signoff.md) and tick Product
      verification. Then follow
      /plumbline:signoff (<plugin>/skills/signoff/SKILL.md): gap check, full
      suite, push, PR. If the gap check lists gaps, send each to its owner and
      run it again.
7. **Full.** Requires teams (step 3). Run
   `bash <plugin>/scripts/kickoff.sh <module> <feature-slug> --profile full --ux --surfaces <s1,s2>`
   (or `--no-ux`), adding `--new-module` when the block says the module is new,
   then create the branch from the printed folder as in 6.1. For a new module,
   product writes vision.md first. Then the full flow:
   discovery (follow <plugin>/skills/discover/SKILL.md yourself, since it asks
   the user; product writes the journeys into ux.md) → spec, criteria and
   ux.md (product, as in 6.2) → lead's plan (as in 6.3) → the user approves →
   READY and make-briefs.sh → team build (teammates from the plan's Team
   table, spawned as in 6.4) → QA, product verification and signoff as in 6.5
   (give QA the same brief, with "Full:" in place of "Standard:").
8. **Questions, waivers and cleanup** (any size).
   - When an agent returns a question only the user can answer, ask it, then
     pass the answer back to that agent.
   - Agents can't write `Evidence waived:` lines; the ownership guard blocks
     them. When an agent or the gap check reports evidence that can't be
     produced, ask the user, once per evidence kind and surface (several
     questions in one call is fine): waive it (with the reason) or get it done. Only after an explicit
     yes for it, add the line yourself to the feature's qa-report.md, on its
     own line:
     `Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)`,
     where <name> is the user's name (`git config user.name`, else ask).
   - Cleanup on stop: delete `.claude/plumbline-quick` if you wrote it.
9. **No shell** (e.g. eval runs). Do steps 1-3 as usual. Then:
   - Quick: skip step 4, the branch and the marker. Dispatch the lead as in 5.2, adding
     "No shell: no branch, commits, checks or PR. Quick change: no feature
     folder; don't write phase docs. Write the tests, named after the IDs, and
     the code." Report that the change is uncommitted and unchecked, and the
     commands to run once a shell is available.
   - Standard or Full: create the feature folder by hand, as the hand fallback
     in <plugin>/skills/kickoff/SKILL.md describes (with the block's
     surfaces), then stop: building needs a shell for git and the tests.
