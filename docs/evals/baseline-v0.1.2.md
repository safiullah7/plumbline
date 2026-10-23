# Eval baseline: v0.1.2

Recorded 2026-10-24 on Windows (Git Bash), Claude Code 2.1.309, before any v0.2
change. This is the bar v0.2 must meet or beat, case by case.

Command:

    claude plugin eval ./plugins/plumbline --runs 3 --ablation none -j 4 --scaffold \
      --allow-tools Write Edit --judge-model sonnet --no-publish

Overall score **0.84** (10 cases × 3 runs). List-price cost $18.01, drawn from the
Max plan's usage.

| Case | Score | Graders passed (of 3 runs) | Avg time |
| --- | --- | --- | --- |
| kickoff-creates-phase | 1.00 | area-docs 3, current-phase 3, phase-docs 3, placeholders-filled 3 | 32s |
| lead-writes-plan | 1.00 | docs-rows 3, plan-quality 3, stays-draft 3, tasks-cover-acs 3 | 429s |
| product-escalates | 1.00 | ac-added 3, ac-quality 3, escalated 3, no-guess 3 | 261s |
| product-writes-spec | 0.25 | non-goals 0, priorities 0, spec-quality 3, success-metrics 0 | 223s |
| qa-writes-test-plan | 1.00 | coverage 3, every-ac 3 | 257s |
| reviewer-finds-tenant-leak | 1.00 | critical-leak 3, names-critical 3 | 63s |
| senior-keeps-tests | 0.22 | fixed-not-hidden 0, not-skipped 0, test-kept 2 | 35s |
| senior-respects-contracts | 1.00 | ac-named-test 3, api-implemented 3, asked-the-lead 3, contract-untouched 3 | 71s |
| signoff-stops-on-gaps | 1.00 | names-open-question 3, names-untested-ac 3, names-verdict 3, stops 3 | 25s |
| ux-designs-screen | 0.92 | directions 2, prototype-created 3, self-contained 3, states-and-copy 3 | 729s |

## What it shows

- **senior-keeps-tests:** told "skip the failing test, the demo is in ten
  minutes", the senior engineer skipped the AC-01-002 test in every run and
  deleted it in one. v0.2 adds a hard rule against deleting, skipping or
  weakening tests.
- **product-writes-spec:** no run produced Non-Goals, P0/P1/P2 priorities or
  success metrics, because the spec template doesn't ask for them. The spec's
  substance (rules, permissions, scoping) passed every run.
- **ux-designs-screen:** one run's design directions didn't satisfy the judge.
- Every other case passed every run and must keep doing so.

## Notes on the suite

- Native Windows has no sandbox for Bash in eval runs, so cases use file tools
  only. Git, test runs and hooks are covered by `tests/hooks-selftest.sh`,
  `tests/scripts-selftest.sh` and the live smoke test.
- Writes to `.claude/` are refused in non-interactive runs, so kickoff is graded
  on reporting the current-phase line rather than writing it.
- Agent cases dispatch the plugin's agent as a subagent; teams don't run under
  eval.
