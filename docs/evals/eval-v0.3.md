# Eval results: v0.3

Recorded 2026-10-24 with the same settings as v0.2 (3 runs per case, Sonnet
judge, no baseline arm, at most 2 runs in parallel). Every case whose agent,
skill or template changed was rerun, plus three new cases. Cases whose agent and
skill didn't change keep their v0.2 result.

| Case | v0.2 | v0.3 | List-price cost v0.2 → v0.3 |
| --- | :---: | :---: | --- |
| signoff-stops-on-gaps | 1.00 | 1.00 | $0.18 → $0.20 |
| kickoff-creates-phase | 1.00 | 1.00 | $0.48 → $0.50 |
| product-escalates | 1.00 | 1.00 | $1.31 → $1.41 |
| product-writes-spec | 1.00 | 1.00 | $2.50 → $2.30 |
| qa-writes-test-plan | 1.00 | 1.00 | $3.03 → $4.85 |
| lead-writes-plan | 1.00 | 1.00 | $4.92 → $6.12 |
| ux-designs-screen | 1.00 | 1.00 | $8.70 → $7.21 |
| product-respects-decisions (new in v0.3; baseline run on v0.2) | 0.89 | **1.00** | $2.85 → $2.50 |
| phase-next-proposes (new) | — | 1.00 | $0.21 |
| qa-runner-no-browser (new) | — | 1.00 | $0.47 |
| reviewer-finds-tenant-leak (unchanged) | 1.00 | 1.00 (carried) | — |
| senior-keeps-tests (unchanged) | 1.00 | 1.00 (carried) | — |
| senior-respects-contracts (unchanged) | 1.00 | 1.00 (carried) | — |
| discover-asks-first (unchanged) | 0.89 | 0.89 (carried) | — |

No case scores below its v0.2 result.

## Notes

- **product-respects-decisions** was written first and run on v0.2 as its
  baseline. In one of three runs the v0.2 product engineer let a teammate's
  suggestion override a recorded decision. On v0.3 it kept the decision in every
  run.
- **qa-writes-test-plan** costs more because the test plan now includes a
  screenshot comparison and an accessibility scan for every key screen, as
  intended. **lead-writes-plan** also rose; its plan now carries a qa-runner
  ownership row and the scripts path. **ux-designs-screen** fell.
- The new visual and accessibility scripts can't run inside eval runs (no shell
  on native Windows), so they're covered by `tests/scripts-selftest.sh` (66
  checks, including a decoder test against a real browser screenshot) and an
  opt-in real-browser test (`PLUMBLINE_BROWSER_TEST=1`), which passed 3/3 on
  Chrome.
- **Known limit of the visual comparison:** it compares 8×8 block averages, so a
  missing column of text (as opposed to a moved, missing or recoloured element)
  barely registers. A test drift with a removed text column scored 6.8% and
  wasn't flagged. A candidate for v0.4.
