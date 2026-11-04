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
step. Run only the steps below and add none of your own: no extra test run
(a "clean verification"), no attack round for a deferred finding. Dispatch
agents without a `name`, except where a step spawns teammates:
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
   Split: 1 of <n> — <nn> <slice> (this) · <nn+1> <slice> · ...
   Folder: none | docs/product/<module>/<nn>-<feature-slug>/
   Surfaces: <comma-separated>
   Roles: <e.g. product, lead, 2 engineers, reviewer, QA>
   Evidence: <one kind per surface, e.g. web-ui: journeys; api: transcripts>
   Security: none | attacks | independent
   UX: yes | no
   Engineers: <n>
   Docs: none | slim | full
   Team: no | yes
   Why: <one line>
   ```

   The `Split:` line is there only when triage split the request (a feature
   is at most ~30 criteria and ~6 screens); never add one yourself.
   The evidence kinds: web-ui and desktop-ui journeys, mobile-ui flow-tests,
   api transcripts, service job-tests, cli golden-output, library
   doc-examples, data sample-run, ai eval-set, infra plan-output.

   Then list the Quick criteria, if any. Ask only when one of these holds:
   - the request is too vague for observable criteria (ask what's missing);
   - triage couldn't decide the size or the module;
   - the size is Full (confirm the commitment, and that teams are on);
   - the block has a `Split:` line (confirm building slice 1 now, the other
     slices becoming planned features in vision.md; with Full, in the same
     question);
   - there's no project.md yet (step 1 asks this, once);
   - Confirm is `always` (confirm the block as a whole).
   Otherwise go straight on. If an answer changes the module, size, surfaces
   or criteria, re-run step 2 with the answers added and print the new block.
   The user may raise the Security level in any answer, never lower it here.
   `independent` is never Quick: a Quick block raised to it is re-triaged as
   Standard (re-run step 2 with that added).
   From here on, dispatch only the roles the Roles line lists. `UX: yes`
   means the feature has UI: product writes ux.md. With a `Split:` line,
   build slice 1 only, and give the line to every product dispatch: product
   writes slice 1 and adds the other slices to the module's vision.md
   Features table. Give no model to the lead,
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
      `bash <plugin>/scripts/ac-check.sh`, `bash <plugin>/scripts/run-bg.sh`
      (servers and long runs; with a team also `plan-tasks.sh` and
      `watch-build.sh` there), and the test commands for each of
      the block's surfaces: PLUMBLINE_TYPECHECK, PLUMBLINE_LINT and
      PLUMBLINE_TEST_AC if set; else that surface's Typecheck, Lint and AC
      tests cells in project.md (an adapter name runs
      `<plugin>/scripts/ac-tests/<name>.sh`); else `npm run -s typecheck`,
      `npm run -s lint`, `npm run -s test:ac`; plus each surface's Run command
      (the dev server QA and the e2e tests use) and the browser tool QA drives.
      When the Security line isn't `none`, add
      `bash <plugin>/scripts/security-check.sh`, and say signoff runs the
      attack (SEC) tests against the apps, started through run-bg.sh.
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
      When the Security line is `attacks`, add "Security: attacks. Signals:
      <the signals from the block's Why line>."
      The lead dispatches one senior engineer on sonnet, runs
      `ac-check.sh "<IDs>" --surface <surface>`, gets a review, pushes and
      opens the PR; it never creates a folder or merges. If it reports the
      work outgrew Quick, go back to step 2 with its reasons.
   3. Wrap-up, also after a failure or a cancel: delete `.claude/plumbline-quick`
      and report the PR link (or the compare URL), the `ac-check.sh` result,
      and the reviewer's findings and how each was resolved. If the lead
      stopped before the PR (a SEC ID failed or a Critical or High finding is
      open), relay its report and ask: fix it (dispatch the lead again with
      the report), re-triage as Standard, or stop. Quick has no risk
      acceptance. Medium and low findings don't stop Quick and aren't asked
      about: report them as follow-up work.
6. **Standard.**
   1. From the default branch, run
      `bash <plugin>/scripts/kickoff.sh <module> <feature-slug> --profile standard --ux --surfaces <s1,s2>`
      (`--no-ux` when the block says `UX: no`; <s1,s2> is the Surfaces line
      without spaces; add `--security <level>` when the Security line isn't
      `none`). Its last line is the feature folder; use that path from
      now on, and say so if it differs from the block's. Then create and switch to the branch `feature/<nn>-<feature-slug>`,
      with <nn> from the printed folder, and commit the new docs (and a
      project.md you wrote in step 1) by path.
   2. Dispatch plumbline:product-engineer: write the slim spec.md and
      acceptance-criteria.md for the request in the folder and, if `UX: yes`,
      ux.md: the journeys, the screen inventory and each screen in words
      (layout, components, every state, exact copy).
   3. Dispatch plumbline:lead-engineer to write dev-plan.md (Status: DRAFT,
      engineers by load, usually 1-2 (up to 4)): per engineer, ordered tasks
      with the failing unit test first, the e2e test and a done-when, and the Team table with each
      engineer's Effort. Before the question, show the plan itself, read from
      dev-plan.md (not only the lead's prose), as a short review in this order:
      the file path; the Team table (engineer, workstream, surface, effort);
      per engineer, one line per task (IDs, title, rating); the contracts
      that land first; the attack plan (level, row count, `Attack surface:`,
      and each row's ID and attack in a few words; the first 12 and "+n more"
      when longer); the key decisions; the risks; and the plan's open items
      for the user. If the Team table has a row that isn't a senior engineer
      (qa, qa-runner, product), or the plan names a model or QA tool the
      current roles don't have, send it back to the lead before asking. Then
      ask once: approve the plan, or change it (say what); in the same call,
      batch product's open questions (questions.md rows still OPEN) and the
      plan's open items for the user, so the user answers everything at
      once. Pass each answer to its owner. Relay changes to the lead until
      approved.
      When the Security line isn't `none`, the dispatch also gives the level
      and the signals from the block's Why line; the lead adds the `## Attack
      plan`. Before the question, if dev-plan.md has a `Security level:` line, run
      `bash <plugin>/scripts/kickoff.sh --set-security <level>` (commit what
      it changed by path); then run
      `bash <plugin>/scripts/security-check.sh --no-run` and act on the levels
      and plan rows it prints, never on prose (a line it can't read goes back
      to the lead; `Checked`, findings and the independent pass come later,
      so don't present those gaps to the user as problems at this point).
      With the question show the required level, the attack plan's row count
      and its `Attack surface:` line, and say the user can raise the level
      (run `--set-security` and send the lead back to plan for it) or waive a
      part (step 8).
   4. Tell the lead the plan is approved: it sets READY, runs make-briefs.sh and
      builds, dispatching each engineer as a subagent on sonnet with that
      engineer's Effort, reviewing each workstream against the plan,
      dispatching a reviewer per workstream and checking each with
      `ac-check.sh "<its IDs>" --surface <its surface>`. With 2 or more engineers
      and teams on (and always for Full), spawn the team yourself instead, each
      teammate with the Agent tool, its agent type and its name (call
      TeamCreate first if your Claude Code has it). Teammates can't spawn
      teammates, so you spawn them all, in this order:
      1. The lead first, agent type plumbline:lead-engineer, name `lead` (you
         are `team-lead`): "The plan is approved. Setup: set READY, run
         make-briefs.sh, commit the docs and contracts/ (L0), run
         plan-tasks.sh and create every task it prints (owner, blockedBy),
         then report "ready" to team-lead. Then run the build; engineers
         report to you." Then run
         `bash <plugin>/scripts/watch-build.sh --sleep 60` in the foreground
         and run it again until it stops printing `NO-TASKS` (the lead has
         created the tasks) or the lead reports "ready". Spawn no engineer
         before that.
      2. Then each engineer in the plan's Team table: agent type
         plumbline:senior-engineer, its name, model sonnet and `effort` from
         its Effort column, with this prompt filled in:
         ```
         You are <name>, a senior engineer on <folder>. Effort: <effort>. Surface: <surface>.
         Your brief: <folder>/briefs/<name>.md (read it once). Your tasks: <folder>/briefs/<name>/ (read each task's <label>.md when you start it).
         Report to `lead`, never to team-lead.
         Claim (TaskUpdate in_progress) and complete tasks in the shared list, in order; keep going through your ready tasks without waiting for a verdict.
         After a report, start your next ready task in the same turn; never end a turn on an announcement.
         ```
      3. Watchdog: never wait passively for notifications; hooks wake no one
         (a hook's `systemMessage` reaches only the user). Run
         `bash <plugin>/scripts/watch-build.sh --sleep 300` in the foreground
         (Bash timeout 600000; it flags a teammate after 5 minutes without
         progress), act on its output, and run it again, until it prints
         `DONE` (every task, the lead's chores included, is completed) and the
         lead has reported the build done (acceptance, reviews, at
         `independent` the attack round, then its `--all` run). For each
         `STALLED: <name> (<task>)` line, SendMessage that teammate
         `Continue: <task>`. For `STALLED: lead`, or a `LEAD: <chores>` line
         while the lead shows no activity, message `lead` to run each finished
         workstream's acceptance check and review. Never relay reports: one
         that reaches you is forwarded to `lead` once, and you tell its sender
         to report to `lead`.
      When every workstream is accepted and reviewed, the lead ticks
      "Integration review" in signoff.md (no full suite yet). At
      `independent`, the lead then runs the attack round, before QA. Last,
      it runs the whole suite once per surface (`ac-check.sh --all`) and
      reports the build done. A `Security level:` raise during the build is
      handled as in 6.3. When the lead returns "Needs user", handle it as in
      step 8.
   5. Verify. Dispatch plumbline:qa-engineer to test the flows (functional
      only) with: "Standard: check each journey and criterion works, fill
      test-plan.md Traceability, log bugs in qa-report.md, record the Evidence
      row for each surface's required kind, set the Verdict and tick the QA
      verdict box. Required evidence: <the block's Evidence line>." Dispatch
      plumbline:product-engineer to walk the finished journeys against the criteria (Journey results, Product
      findings, Success metrics results in signoff.md) and tick Product
      verification. Then follow
      /plumbline:signoff (<plugin>/skills/signoff/SKILL.md): leftover runs
      stopped, gap check, the whole suite (`ac-check.sh --all`, usually
      reusing the lead's run), push, PR. If the gap check lists gaps, send
      each to its owner and run it again.
7. **Full.** Requires teams (step 3). Run
   `bash <plugin>/scripts/kickoff.sh <module> <feature-slug> --profile full --ux --surfaces <s1,s2>`
   (or `--no-ux`), adding `--new-module` when the block says the module is new
   and `--security <level>` (at least `attacks` for Full),
   then create the branch from the printed folder as in 6.1. For a new module,
   product writes vision.md first. Then the full flow:
   discovery (follow <plugin>/skills/discover/SKILL.md yourself, since it asks
   the user; product writes the journeys into ux.md) → spec, criteria and
   ux.md (product, as in 6.2) → lead's plan (as in 6.3) → the user approves →
   the lead's setup (READY, make-briefs.sh, the task list) → team build
   (teammates from the plan's Team table, spawned as in 6.4, with the
   watchdog) → QA, product verification and signoff as in 6.5
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
   - Security lines work the same way (agents can't write them either): only
     after the user's explicit yes, add the line yourself to the feature's
     security.md, on its own line:
     `Security waived: <attacks|independent> - <reason> (approved by <name>)`
     (it removes only the part it names);
     `Risk accepted: #<n> <severity> <the finding text exactly as in the row> - <reason> (approved by <name>)`;
     `Risk accepted: secret <path> - <reason> (approved by <name>)` for a
     secrets-scan hit. When the lead returns "Needs user" with open rows, or
     the gap check lists an open critical or high finding or a secret, ask
     per row or path: fix again, accept the risk, or stop. In attack rounds
     1-3 recommend "fix again"; after three rounds (the lead's "Needs user"),
     recommend none. Write the lines the user approved, then dispatch the
     lead again with the answers. Never in Quick: it has no waivers or
     acceptances.
   - Medium and low findings are never asked about: the attacker defers them
     (status `deferred`, the attack test marked as an expected failure). Your
     final report lists them, and any accepted risk, as follow-up work.
   - Processes: agents start servers and long runs through
     `bash <plugin>/scripts/run-bg.sh` and stop them. Never ask the user to
     stop one: `run-bg.sh list` shows what's running, and
     `run-bg.sh stop <name>` (or `stop --all`) stops it with its children.
     Never stop a process by name or pattern.
   - Cleanup on stop: delete `.claude/plumbline-quick` if you wrote it, and
     run `bash <plugin>/scripts/run-bg.sh stop --all`.
9. **No shell** (e.g. eval runs). Do steps 1-3 as usual. Then:
   - Quick: skip step 4, the branch and the marker. Dispatch the lead as in 5.2, adding
     "No shell: no branch, commits, checks or PR. Quick change: no feature
     folder; don't write phase docs. Write the tests, named after the IDs, and
     the code." Report that the change is uncommitted and unchecked, and the
     commands to run once a shell is available.
   - Standard or Full: create the feature folder by hand, as the hand fallback
     in <plugin>/skills/kickoff/SKILL.md describes (with the block's
     surfaces and security level), then stop: building needs a shell for git and the tests.
