# Plumbline v0.6 evals

Run on branch `v0.6` (2026-11-01) with `claude plugin eval --runs 3
--ablation none --scaffold --allow-tools Write Edit --judge-model sonnet
--no-publish`, one case at a time. Baseline: `docs/evals/eval-v0.5.md`.

Rerun: every case whose agent or skill prompt changed in v0.6 (triage,
product spec, lead, senior, the attacker, the Quick cases) plus the four new
cases. Not rerun, because nothing they load changed: discover, kickoff,
signoff, phase-next, the reviewer cases, `qa-checks-functionality`,
`product-escalates`, `product-respects-decisions`, `product-writes-ui-text`,
`build-first-run-profile`.

| Case | v0.5 | v0.6 | Note |
| --- | :---: | :---: | --- |
| attacker-finds-planted-hole | 1.00 | 1.00 |  |
| build-quick-dispatches | 1.00 | 1.00 |  |
| lead-labels-and-dependencies (new) | — | 1.00 (first 0.90) | every task labelled, dependent tasks have `Blocked by:`, plan stays DRAFT; see "Lead writes before approval" below |
| lead-plans-mock-first (new) | — | 1.00 (first 0.96) | UI tasks built against a mock of the contract, one switch-to-the-real-API task blocked by the API task, at most 12 tasks |
| lead-plans-tdd-unit-e2e | 1.00 | 1.00 |  |
| lead-writes-attack-plan | 0.98 | 1.00 | 0.98 in one of six earlier runs: that plan had no attack row the check reads as a by-ID read of another clinic's room |
| lead-writes-plan | 1.00 | 1.00 |  |
| product-writes-spec | 1.00 | 1.00 |  |
| quick-by-id-gets-attacks | 1.00 | 1.00 |  |
| quick-review-loop | 1.00 | 1.00 |  |
| senior-continues-to-next-task (new) | — | 1.00 | both tasks' tests written in one run, task 1 first, and the run ends on work, not an announcement (run twice: 1.00 both times) |
| senior-keeps-tests | 1.00 | 1.00 |  |
| senior-respects-contracts | 1.00 | 1.00 |  |
| senior-writes-attack-tests-first | 1.00 | 1.00 |  |
| senior-writes-unit-and-e2e | 1.00 | 1.00 |  |
| triage-asks-when-vague | 1.00 | 1.00 |  |
| triage-data | 1.00 | 1.00 |  |
| triage-full-new-module | 1.00 | 1.00 |  |
| triage-mobile | 1.00 | 1.00 |  |
| triage-new-module-standard | 1.00 | 1.00 |  |
| triage-quick-backend-bug | 1.00 | 1.00 |  |
| triage-security-auth | 1.00 | 1.00 |  |
| triage-security-byid | 1.00 | 1.00 |  |
| triage-security-copy | 1.00 | 1.00 |  |
| triage-splits-big-request (new) | — | 1.00 | a whole-module request gets a `Split:` line with at least two slices and keeps `Size: Full` (run twice: 1.00 both times) |
| triage-standard-screen | 1.00 | 1.00 | not split |
| triage-surfaces-api-only | 1.00 | 1.00 |  |
| triage-surfaces-api-web | 1.00 | 1.00 |  |

**Result:** every case is at or above its v0.5 score, and the four new
cases score 1.00. The five lead cases were rerun after the last lead prompt
change (below) and are the scores shown.

**Lead writes before approval (one grader and one prompt line changed):**
`no-code-write` failed once in three runs of `lead-plans-mock-first` (0.96)
and in all three of `lead-labels-and-dependencies` (0.90); every other check
in both cases passed.
- The check came from v0.5, where the lead wrote only docs while planning.
  v0.6 has the lead write the contracts, the database schema and migrations
  while it plans, so the user approves them with the plan, and the check
  counted a migration as code. It now also allows writes under `contracts/`,
  `migrations/` and to `schema.*`; any other file outside `docs/product`
  still fails it (checked against nine sample paths, Windows and POSIX).
- With that change the labels case still failed one run in six. A rerun
  with `--keep-temp` showed why: the lead also wrote a `docker-compose.yml`
  and a test-database init script while planning, listed as an L0 contract.
  That is setup, not a contract, and it changes the user's repo before the
  plan is approved. `lead-engineer.md` now says: before approval write
  nothing else outside the phase folder; shared dev or test setup
  (docker-compose, a test database, seed scripts, CI) is a task in the plan,
  done after approval. All five lead cases were rerun on that prompt: 1.00
  each.

What the evals can't show: claiming and completing tasks in the shared list,
the idle gate, the watchdog and the per-task checks run only in a live agent
team (evals have no Bash or Task tools). The hooks and scripts behind them are
covered by the self-tests (2,052 checks, 0 failed); the live DineFlow run on
v0.6 measures the speed.

Cost of all v0.6 eval runs: about $95 at list price, of which about $16 was
the four last lead cases running twice by mistake (a run stopped for low
memory kept going while it was restarted).
