# Eval results: v0.4a

Recorded 2026-10-24 on Windows (Git Bash), Claude Code 2.1.310, with the same
settings as v0.2 and v0.3: 3 runs per case, Sonnet judge, no baseline arm, at
most 2 runs in parallel.

    claude plugin eval ./plugins/plumbline --runs 3 --ablation none -j 2 --scaffold \
      --allow-tools Write Edit --judge-model sonnet --no-publish

Every agent changed in v0.4a, so every case was rerun (21 cases × 3 runs, 82
minutes), not just the new ones. Four cases were then rerun after the fixes
described in the notes. List-price cost about $35, drawn from the Max plan's
usage.

| Case | v0.3 | v0.4a | List-price cost v0.3 → v0.4a |
| --- | :---: | :---: | --- |
| signoff-stops-on-gaps | 1.00 | 1.00 | $0.20 → $0.19 |
| kickoff-creates-phase (the legacy kickoff form) | 1.00 | 1.00 | $0.50 → $0.52 |
| product-escalates | 1.00 | 1.00 | $1.41 → $1.44 |
| product-writes-spec | 1.00 | 1.00 | $2.30 → $2.09 |
| product-respects-decisions | 1.00 | 1.00 | $2.50 → $2.47 |
| qa-writes-test-plan | 1.00 | 1.00 | $4.85 → $4.14 |
| lead-writes-plan | 1.00 | 1.00 | $6.12 → $5.31 |
| ux-designs-screen | 1.00 | 1.00 | $7.21 → $7.87 |
| phase-next-proposes | 1.00 | 1.00 | $0.21 → $0.20 |
| qa-runner-no-browser (grader updated, see notes) | 1.00 | 1.00 | $0.47 → $0.41 |
| reviewer-finds-tenant-leak | 1.00 | 1.00 | carried → $0.52 |
| senior-keeps-tests | 1.00 | 1.00 | carried → $0.39 |
| senior-respects-contracts (grader updated, see notes) | 1.00 | 1.00 | carried → $0.51 |
| discover-asks-first | 0.89 | 0.89 | carried → $0.22 |
| **triage-quick-backend-bug** (new) | — | 1.00 | $0.45 |
| **triage-standard-screen** (new) | — | 1.00 | $0.44 |
| **triage-full-new-module** (new) | — | 1.00 | $0.37 |
| **triage-new-module-standard** (new) | — | 1.00 | $0.41 |
| **triage-asks-when-vague** (new) | — | 1.00 | $0.43 |
| **build-quick-dispatches** (new) | — | 1.00 | $2.03 |
| **kickoff-module-feature** (new) | — | 1.00 | $0.46 |

No case scores below its v0.3 result. "Carried" means v0.3 kept the v0.2 result
without a rerun, so there's no v0.3 cost to compare.

## What the new cases show

- **Triage sizes the work correctly** in every run:
  - a backend bug is Quick with no folder, no UX and one engineer;
  - a new screen in an existing module is Standard, in `docs/product/rooms/<nn>-…`, with UX;
  - a billing module from scratch is Full, new module, 2–4 engineers, full docs;
  - a feature for a module that has code but no docs folder is Standard with a new module folder.

  Each triage costs about $0.14 per run.
- **A vague request gets a question, not work.** "Make the rooms better" was
  answered with a clarifying question every time, and no lead or engineer was
  dispatched.
- **The Quick flow runs end to end without a shell.** The flow went product
  (triage), then lead, then one senior engineer, then a code reviewer.
  - The test was named after the `AC-<yymmdd>-<nn>` ID and the fix landed.
  - No feature folder was created.
  - It costs about $0.68 per run, against $5–8 for a single Full-flow role
    such as the lead's plan or the UX design.
- **The module-form kickoff, done by hand** (no shell), creates
  `docs/product/rooms/02-room-schedules/` with the slim spec, `.plumbline` and
  the right number.

Git, branches, `ac-check.sh`, pushes and PRs can't run inside eval runs. The live
smoke test covers them.

## Notes

- **The triage rule was clarified during authoring.**
  - **What happened:** the first trial of triage-new-module-standard scored
    0.50. The plan said both that "a new module" is Full, and that a Standard
    feature creates a missing module folder.
  - **The rule now:** a module is "new" when `docs/product/<module>/` doesn't
    exist, even if its code does. Full's trigger is a module built from
    scratch. The product engineer, the plan and the README say the same.
- **qa-runner-no-browser: the grader followed a rule v0.4a changed on purpose.**
  - **The old grader:** it asked for the runner to request a waiver line from
    the product engineer. That was v0.3's rule.
  - **v0.4a's rule:** only the user can approve a waiver, and the build skill
    writes the line. The hooks now block agents from writing one.
  - **What failed:** two of three runs did exactly that and failed. The first
    run of this case scored 0.78.
  - **The new grader:** it asks for the v0.4a behaviour: the runner says the
    scan needs the user's waiver and doesn't write the line itself. The other
    two graders (no invented counts, "not run" recorded) are unchanged.
  - **Result:** 1.00 on rerun.
- **senior-respects-contracts: the grader judged the wrong text.**
  - **What failed:** the first run scored 0.92 and a rerun 0.83. In each
    failing run the case's LLM grader failed because the main session's
    summary dropped the `AC-01-002` prefix from the test names.
  - **What actually happened:** a probe run that kept its files shows the
    engineer did name every test `it('AC-01-002 …')`.
  - **The fix:** the grader now checks the test the engineer wrote, with a
    regex over the run's trace. Stripping the prefix from the trace makes it
    fail, so it isn't vacuous. Result: 1.00, 3 of 3.
  - **Agent change:** the senior engineer is now told to report each test by
    its full name in every mode, not just in Quick. senior-keeps-tests and
    build-quick-dispatches were rerun after that change and stayed at 1.00.
- **discover-asks-first** failed its "hard parts" judge in one run of three, the
  same as v0.2 and v0.3. Its skill didn't change in v0.4a.
- **Self-tests at the time of this run:** 760 checks across all suites,
  0 failed (`bash tests/run-all.sh`).
