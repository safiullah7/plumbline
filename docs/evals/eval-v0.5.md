# Plumbline v0.5 evals

Run on branch `v0.5` (2026-10-30) with `claude plugin eval --runs 3
--ablation none --scaffold --allow-tools Write Edit --judge-model sonnet
--no-publish`, one group at a time. Baseline: `docs/evals/eval-v0.4b.md`
(lean roles), where every case below scored 1.00 except
`product-writes-ui-text` (0.97).

Rerun: every case whose agent or skill prompt changed (triage, product spec,
lead, senior, reviewer, the two Quick cases) plus the eight new cases. Not
rerun, because nothing they load changed: discover, kickoff, signoff,
phase-next, `qa-checks-functionality`, `product-escalates`,
`product-respects-decisions`, `product-writes-ui-text`, `build-first-run-profile`.

| Case | Before | v0.5 | Note |
| --- | :---: | :---: | --- |
| attacker-finds-planted-hole (new) | — | 1.00 | first run did not load: a grader file lacked its closing `---` |
| build-quick-dispatches | 1.00 | 1.00 |  |
| lead-plans-tdd-unit-e2e | 1.00 | 1.00 (first 0.95) | 0.95 first: an LLM judge failed long plans (20-29k chars); all three kept plans met every point when read by hand; replaced by two exact checks |
| lead-writes-attack-plan (new) | — | 0.98 | an LLM judge found one attack row too vague in one run |
| lead-writes-plan | 1.00 | 1.00 |  |
| product-writes-spec | 1.00 | 1.00 |  |
| quick-by-id-gets-attacks (new) | — | 1.00 (first 0.83) | 0.83 first: the grader read the run log, which does not show the engineer's writes two levels down; now reads the test file |
| quick-review-loop | 1.00 | 1.00 |  |
| reviewer-api-authz | 1.00 | 1.00 |  |
| reviewer-cli-interactive | 1.00 | 1.00 |  |
| reviewer-finds-tenant-leak | 1.00 | 1.00 |  |
| reviewer-flags-soft-attack-test (new) | — | 0.92 | flagged the soft test in every run; named the missing list item in two of three |
| reviewer-single-tenant | 1.00 | 1.00 |  |
| senior-keeps-tests | 1.00 | 1.00 |  |
| senior-respects-contracts | 1.00 | 1.00 |  |
| senior-writes-attack-tests-first (new) | — | 1.00 |  |
| senior-writes-unit-and-e2e | 1.00 | 1.00 |  |
| triage-asks-when-vague | 1.00 | 1.00 |  |
| triage-data | 1.00 | 1.00 |  |
| triage-full-new-module | 1.00 | 1.00 |  |
| triage-mobile | 1.00 | 1.00 |  |
| triage-new-module-standard | 1.00 | 1.00 |  |
| triage-quick-backend-bug | 1.00 | 1.00 |  |
| triage-security-auth (new) | — | 1.00 |  |
| triage-security-byid (new) | — | 1.00 |  |
| triage-security-copy (new) | — | 1.00 |  |
| triage-standard-screen | 1.00 | 1.00 |  |
| triage-surfaces-api-only | 1.00 | 1.00 |  |
| triage-surfaces-api-web | 1.00 | 1.00 |  |

**Result:** every rerun case is at or above its v0.4b score, and the eight
new cases score 0.92 to 1.00.

**Graders changed after the first runs (three, all in new or rerun cases):**
- `attacker-finds-planted-hole`: a missing closing `---` kept the case from
  loading; fixed, then 1.00.
- `quick-by-id-gets-attacks`: the attack-test check read the run log; the
  engineer works two levels below the build skill and its writes are not in
  that log, so the check could never pass. It now reads the test file, as
  `quick-review-loop` does. Every other check passed on the first runs.
- `lead-plans-tdd-unit-e2e`: the plan-consistency LLM judge failed two of
  three runs with the eval tool's own warning that judges are noisy on long
  files. The three plans (kept with `--keep-temp`) were read by hand: every
  task had all seven lines, each engineer's Effort matched its highest task,
  the authorization and tenant tasks were HIGH, and all five criteria were
  covered. The judge was replaced by two exact checks (the authorization or
  tenant task is HIGH; every criterion is in a task subject), which pass on
  all three plans and fail on counter-examples.

Plans are longer than in v0.4b: the attack catalogue adds edge cases such as
"a ?clinicId= query is ignored", and the lead raised the level to
`independent` (with an attack plan) in one of three runs of a case with
authorization and tenant criteria, which the rubric allows.

Cost of all v0.5 eval runs, including the reruns: about $50 at list price.
