# Eval results: v0.4b

> **Superseded (2026-10-27).** The "lean roles" change removed some of the cases and scripts
> listed here (the UX engineer and QA runner cases, the QA planning cases, the visual and
> accessibility checks, the `Models:` triage cases) and changed the agents behind the rest.
> New results will be recorded here later. Until then, treat the numbers below as the
> pre-change run.

Recorded 2026-10-26 on Windows (Git Bash), Claude Code 2.1.310, with the same
settings as v0.4a: 3 runs per case, Sonnet judge, no baseline arm.

    claude plugin eval ./plugins/plumbline --runs 3 --ablation none -j <1-3> --scaffold \
      --allow-tools Write Edit --judge-model sonnet --no-publish

Every agent changed in v0.4b, so every case was run (37 cases × 3 runs). The
cases the later changes touched (the Opus lead, model allocation, the kickoff
fix) were rerun afterwards; the table shows each case's final run. Costs are
list price for the three runs, drawn from the Max plan's usage; the whole
v0.4b eval effort, including the reruns and a duplicated run (see the notes),
came to about $60.

| Case | v0.4a | v0.4b | Cost (3 runs) |
| --- | :---: | :---: | --- |
| build-first-run-profile (new) | — | 0.92 (one run triaged before asking about the profile) | $0.31 |
| build-quick-dispatches | 1.00 | 1.00 | $3.07 |
| discover-asks-first | 0.89 | 1.00 | $0.24 |
| kickoff-creates-phase | 1.00 | 1.00 | $0.54 |
| kickoff-module-feature | 1.00 | 1.00 (0.00 before the kickoff fix; 1.00 after) | $0.57 |
| lead-writes-plan | 1.00 | 1.00 | $6.77 |
| phase-next-proposes | 1.00 | 1.00 | $0.25 |
| product-escalates | 1.00 | 1.00 | $2.06 |
| product-respects-decisions | 1.00 | 1.00 | $2.52 |
| product-writes-spec | 1.00 | 1.00 | $2.21 |
| qa-plan-ai (new) | — | 1.00 | $4.12 |
| qa-plan-api (new) | — | 1.00 | $3.34 |
| qa-plan-mobile (new) | — | 1.00 | $3.85 |
| qa-runner-no-browser | 1.00 | 1.00 | $0.44 |
| qa-writes-test-plan | 1.00 | 1.00 | $3.17 |
| quick-review-loop (new) | — | 1.00 (0.90 on the Sonnet lead; 1.00 on Opus) | $3.77 |
| reviewer-api-authz (new) | — | 1.00 | $0.84 |
| reviewer-cli-interactive (new) | — | 1.00 | $0.51 |
| reviewer-finds-tenant-leak | 1.00 | 1.00 | $0.50 |
| reviewer-single-tenant (new) | — | 1.00 | $0.80 |
| runner-mobile-no-device (new) | — | 1.00 | $0.64 |
| senior-keeps-tests | 1.00 | 1.00 | $0.40 |
| senior-respects-contracts | 1.00 | 1.00 | $0.55 |
| signoff-stops-on-gaps | 1.00 | 1.00 | $0.22 |
| triage-asks-when-vague | 1.00 | 1.00 | $0.55 |
| triage-data (new) | — | 1.00 | $0.53 |
| triage-full-new-module | 1.00 | 1.00 | $0.47 |
| triage-mobile (new) | — | 1.00 | $0.55 |
| triage-models-high-risk (new) | — | 1.00 | $0.58 |
| triage-models-routine (new) | — | 1.00 | $0.52 |
| triage-new-module-standard | 1.00 | 1.00 | $0.50 |
| triage-quick-backend-bug | 1.00 | 1.00 | $0.53 |
| triage-standard-screen | 1.00 | 1.00 | $0.53 |
| triage-surfaces-api-only (new) | — | 1.00 | $0.48 |
| triage-surfaces-api-web (new) | — | 1.00 | $0.53 |
| ux-designs-screen | 1.00 | 1.00 | $7.36 |
| ux-mobile-mockups (new) | — | 0.96 (one grader missed once) | $5.46 |

No case scores below its v0.4a result. `discover-asks-first` rose from 0.89 to
1.00.

## What the new cases show

- **Triage by surface** works on every fixture: api plus web (UX yes), api only
  (no UX, no design), Flutter (mobile-ui, flow tests, no browser), a data
  pipeline (sample runs, idempotency).
- **Test plans fit the surface:** emulator screenshots, flow tests and a
  checklist for mobile with no URL; contract, authorization, negative cases and
  transcripts for an API; an eval set with a numeric threshold, injection cases
  and budgets for an AI service.
- **The runner is honest without a device:** `not run` rows, the boot command
  recorded, no waiver written.
- **Reviewers by surface:** a missing authorization check is Critical; an
  interactive prompt on a non-interactive CLI path is flagged; a single-tenant
  project gets no tenant findings.
- **UX for mobile:** device-size mockups at 390×844 and 430×932, platform
  notes and a checklist plan, with no axe or `capture.mjs`.
- **The first run asks about the profile** and dispatches no engineer until the
  user answers.
- **Model allocation:** a routine change keeps everything except the lead on
  Sonnet; a refunds-with-permissions change puts product and QA on Opus; the
  lead is never dispatched with a cheaper model (a grader in both Quick cases).

## Notes

- **The Sonnet-lead trial was rejected.** v0.4b tried running the Quick-mode
  lead on Sonnet to cut the Quick cost. In `quick-review-loop` the Sonnet lead
  skipped the code review in one run of three on two separate occasions (0.90).
  With the lead back on Opus the case scored 1.00 on three runs, and
  `build-quick-dispatches` held at 1.00. Safi's rule now: the lead is always
  Opus, plans step by step, and never writes code; the Sonnet engineers do.
- **Model allocation by complexity** was added after that: the triage block's
  `Models:` line, a rubric per role, and the build skill dispatching each role
  with its model. The two `triage-models-*` cases cover it; their first run was
  skipped by a YAML error in their descriptions (a colon), fixed before the
  recorded run.
- **kickoff-module-feature scored 0.00 once**, after the review fixes made
  `/plumbline:kickoff` ask which surfaces a feature touches whenever a profile
  exists. The fixture now has a profile, so the skill asked and created
  nothing. Kickoff now takes the surfaces from the profile itself; rerun 1.00.
- **Two runs were killed for low memory,** and both loops kept running after
  the kill, so for a while two eval scripts ran at once and some product and
  QA cases ran twice (about $7 of duplicated runs). The rule since: one eval
  script at a time, cheap cases first, 2–3 in parallel by free RAM.
- **Agent bodies grew** from about 440 to 650 lines with the by-surface
  sections; per-case costs rose by roughly 10–20% on the cases that dispatch
  Opus agents (e.g. lead-writes-plan $5.31 → $6.77). No case lost quality.
- **Self-tests at the time of the recorded runs:** 1261 checks, 0 failed
  (`bash tests/run-all.sh`).
