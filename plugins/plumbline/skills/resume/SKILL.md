---
name: resume
description: Pick up an interrupted feature where it stopped - read its state from the phase docs and git, show what's left, then run the remaining stages (build, attack round, QA, product verification, signoff) through to the PR.
disable-model-invocation: true
argument-hint: "[feature folder, e.g. docs/product/staff-portal/02-staff-order-queue]"
---
Arguments: optional, the feature folder to resume. Without one, the active
phase (.claude/current-phase).

You run in the main session, as in /plumbline:build (<plugin>/skills/build/SKILL.md,
"build" below; <plugin> is the folder two levels above this SKILL.md). Its rules
hold here: ask with AskUserQuestion (your recommended option first), dispatch in
the foreground and wait, give no model to the lead or product, engineers on
sonnet with their Effort, and only the user writes waiver and risk lines
(build step 8). Never redo finished work: what's committed and passing stays.

1. **Settings.** Do build step 1 (shell, repo root, teams, profile, confirm
   mode). Without a shell, stop: resuming reads git and runs the checks.
   - Quick marker: if `.claude/plumbline-quick` exists, an interrupted Quick
     change is waiting. Read its `branch=` and `ids=` lines and ask: resume it
     (recommended) or clear the marker. To resume, switch to that branch and
     dispatch plumbline:lead-engineer with build step 5.2's Quick brief plus:
     "Resume: this branch already has commits for some of these criteria.
     Check what is done (git log, ac-check for the IDs) and finish the rest:
     tests first, review, push, PR." Then do build step 5.3 and stop.
   - Feature: with an argument, write that folder (repo-relative) to
     `.claude/current-phase` if it holds a `.plumbline` file. Without one and
     with no `.claude/current-phase`, list the folders under docs/product/
     whose `.plumbline` exists and whose signoff.md "Merged by the user" box
     is unticked, and ask which to resume.
2. **State.** Run `bash <plugin>/scripts/resume-state.sh` and read every line.
   Also read the newest notes at the top of the feature's progress.md and the
   tail of `git log --oneline` on the feature branch.
   - Branch: if the line says `exists`, switch to the feature branch
     (`git switch <branch>`) once the uncommitted files are settled (below).
     If it says `missing`, stop: say the branch is gone and ask how to go on.
   - `Next:` is the stage to resume at. The independent pass counts only as
     exactly `complete (round <n>)`; anything more (such as "api surface; the
     portal not attacked") leaves the stage at `attack`.
3. **Show and ask, once.** Print, in this order: the feature folder and branch;
   what's done (from the Signoff, Plan and Security lines and the progress
   notes, in a few lines); what's left, as the stages from `Next:` to the PR,
   each with its owner (attack round: lead and an attacker; QA; product
   verification; signoff: you); the open findings and bugs; the uncommitted
   files by owner. In one AskUserQuestion call ask:
   - Resume from <stage> (recommended), or stop.
   - Uncommitted files, when there are any: hand each to its owner to finish
     and commit (recommended: an agent's half-done work, like QA's test
     fixes, is usually worth keeping), stash them (`git stash push -u`), or
     stop. `shared` files (briefs, questions, progress, agent memory) need no
     owner. The owner is the agent that was writing them: the Ownership
     table's, unless the paths or the newest notes say otherwise (a `qa/`
     folder or QA's test files are QA's).
   - Each OPEN question for the user (Questions line), with the question's
     text from questions.md; record each answer in its row (Answer, Status
     ANSWERED) and pass it to the asker when its stage runs.
   With Confirm `auto` and nothing to settle (no uncommitted owned files, no
   user questions), skip the question and go on.
4. **Run the stages**, from `Next:` on. After each one, run resume-state.sh
   again and continue with its `Next:` until it says `merge` or `done`. Give
   every dispatch the line "Resume: an earlier session stopped part-way; read
   what's already in the phase docs and git log first and continue from
   there; don't redo finished work." plus what the state says about its part.
   - `spec` or `plan`: continue the build flow there: build step 6.2 or 6.3
     (Standard) or step 7 (Full), with the plan shown and approved as there.
   - `build`: the plan is approved. With a team (Full, or Standard with 2 or
     more engineers and teams on), spawn as in build step 6.4, the lead first
     (name `lead`) with this setup instead of 6.4.1's: "Resume setup. The plan
     is approved and READY; L0 is done when the docs and contracts are
     committed. Re-run make-briefs.sh. Run plan-tasks.sh and create every task
     (owner, blockedBy). Then mark completed each task already done: its tests
     and code are committed (git log) and its IDs pass in one
     `ac-check.sh "<the plan's IDs on that surface>" --surface <s> --tests-only`
     run per surface; your finished chores too. Report "ready" to team-lead
     with the open tasks per owner." Run watch-build.sh until the tasks exist,
     then spawn only the engineers that have open tasks, from 6.4.2's template,
     and run 6.4.3's watchdog until `DONE` and the lead reports the build done.
     Without a team, dispatch plumbline:lead-engineer with the same setup minus
     the task list: it dispatches each engineer with open work as a subagent.
   - `attack`: dispatch plumbline:lead-engineer (no name): "Resume at the
     attack round, round <n> (one more than the last round in security.md).
     Independent pass: <the Security line's text>. Findings: <the list>.
     Dispatch the attacker as your attack round says, for every attack-plan
     surface not attacked yet, and to verify each finding marked fixed (set a
     finding to fixed first when its fix is committed). Send new Critical or
     High findings to their owners as fix tasks, as there. Report when
     `Independent pass: complete (round <n>)` is written, or Needs user."
     Handle Needs user as in build step 8.
   - `verify`: make sure each surface's Run command from project.md is up (QA,
     the e2e tests and signoff's attack tests use it). Dispatch QA and product
     together, two foreground Agent calls in one message (they write different
     files): plumbline:qa-engineer with build 6.5's QA brief ("Full:" or
     "Standard:" as the size), plus its uncommitted files to finish and commit
     and the bugs to re-test (FIXED rows, and fixes named in git log);
     plumbline:product-engineer to walk the finished journeys as in 6.5. Route
     each bug QA logs to the lead (dispatch it to have the owner fix it, tests
     first, then QA re-tests), and each product finding as in 6.5.
   - `signoff`: follow /plumbline:signoff (<plugin>/skills/signoff/SKILL.md).
     Gaps go to their owners; run it again until it passes and the PR is open.
   - `merge`: the PR is open; the user merges it. Say so and stop.
5. **Report**: the PR link, what this session finished (stages, commits, the
   attack round and QA results), anything still open, and any waiver or risk
   line the user approved. If the user stops part-way, run /plumbline:handoff
   so the next resume starts from notes.
