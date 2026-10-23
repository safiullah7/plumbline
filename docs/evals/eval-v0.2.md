# Eval results: v0.2

Recorded 2026-10-24 with the same command and settings as
[baseline-v0.1.2.md](baseline-v0.1.2.md) (3 runs per case, Sonnet judge, no
baseline arm). Four cases were rerun after the fixes described below; the table
shows each case's latest run.

| Case | v0.1.2 | v0.2 | List-price cost v0.1.2 → v0.2 |
| --- | --- | --- | --- |
| kickoff-creates-phase | 1.00 | 1.00 | $0.35 → $0.48 |
| lead-writes-plan | 1.00 | 1.00 | $3.45 → $4.92 |
| product-escalates | 1.00 | 1.00 | $2.34 → $1.31 |
| product-writes-spec | 0.25 | **1.00** | $1.86 → $2.50 |
| qa-writes-test-plan | 1.00 | 1.00 | $2.18 → $3.03 |
| reviewer-finds-tenant-leak | 1.00 | 1.00 | $0.56 → $0.54 |
| senior-keeps-tests | 0.22 | **1.00** | $0.28 → $0.38 |
| senior-respects-contracts | 1.00 | 1.00 | $0.55 → $0.58 |
| signoff-stops-on-gaps | 1.00 | 1.00 | $0.18 → $0.18 |
| ux-designs-screen | 0.92 | **1.00** | $6.27 → $8.70 |
| **Overall** | **0.84** | **1.00** | **$18.01 → $22.62** |
| discover-asks-first (new) | — | 0.89 | $0.25 |

No case scores below its baseline.

## What changed between the first v0.2 run and the final one

The first v0.2 run had two regressions, both fixed and rerun:

- **product-escalates 1.00 → 0.83.** The criteria were far more thorough (7-9
  per run, covering reactivation, receptionists, tenant isolation, concurrent
  admins and network failure), but some carried "wording pending" or
  "(assumption, see Q3)" inside them, which is a quiet guess. Fix: the product
  engineer writes a criterion complete or not at all; anything that depends on
  an open question waits for the answer. Rerun: 1.00.
- **signoff-stops-on-gaps 1.00 → 0.83.** With no shell to run
  `signoff-check.sh`, the fallback said "stop on any gap", and one run stopped at
  the first gap without checking the rest. Fix: check all five rules, then list
  every gap. Rerun: 1.00.

Also:
- **discover-asks-first** first scored 0 because eval runs can't offer
  AskUserQuestion (they're non-interactive); the skill correctly asked in text
  and didn't write the spec. The graders now accept questions asked in text.
- **product-writes-spec** was rerun because the product engineer changed; it
  stayed at 1.00.
- **ux-designs-screen**'s first v0.2 run had one grader skipped by the cost
  ceiling; the rerun scored 1.00.

## Cost

In these single-role tasks v0.2 costs about 26% more, because the agents do
more of the work that the quality gains come from: research before a spec, a
design brief and critique before a prototype, more thorough criteria and test
plans. v0.2's token savings are aimed at team builds (per-engineer briefs
instead of every engineer reading every doc, context injected at start-up,
answered questions not re-asked, prompt caching), which evals can't measure
because agent teams don't run in non-interactive sessions. The mini-phase
benchmark in `tests/e2e/` measures that.
