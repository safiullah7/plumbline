# Token use: a Quick change (v0.4a)

Recorded 2026-10-24, Claude Code 2.1.310.

## What was measured

One Quick change through `/plumbline:build`, from the eval case
`build-quick-dispatches`: duplicate room names must get a 409, in the rooms
API, on the clinic fixture. The run went:
1. product engineer (triage, Sonnet);
2. lead engineer (Quick mode, Opus);
3. one senior engineer (Sonnet), who wrote the test named `AC-<yymmdd>-<nn>` and the fix;
4. a code reviewer (Sonnet);
5. the wrap-up.

The figures are the session totals Claude Code reports at the end of the run,
subagents included.

The plan was to measure the Quick task from the live smoke test instead. That
session (Claude Code 2.1.310, Sonnet main session) completed the Quick task: every
Part 6 row passed. But it left only a metadata file on disk, not its transcript,
so there was nothing to measure. The eval run is the same flow on the same
agents, without git, `ac-check.sh` and the push, which an eval run can't do.

## Result

| Model | Used by | Input | Cache write | Cache read | Output | List price |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Sonnet | main session, triage, engineer, reviewer | 32 | 47,114 | 190,545 | 9,374 | $0.30 |
| Opus | lead (Quick mode) | 14 | 22,241 | 127,845 | 5,607 | $0.32 |
| **Total** | | 46 | 69,355 | 318,390 | 14,981 | **$0.62** |

Wall time: 148 s. The case's three graded runs cost $2.03–2.26 together, about
$0.70 per run.

## Compared with the full process

A Quick change costs about $0.62. In the Full process, one role's step alone
costs more, at list price per eval run (`docs/evals/eval-v0.4a.md`):
- the lead's dev plan, about $1.80;
- the QA engineer's test plan, about $1.40;
- the UX engineer's screen design, about $2.60.

The full process also adds the team build, QA and signoff. A small fix no
longer pays for any of them.

## Where the cost goes, and a candidate saving

The Opus lead is half of the Quick cost, while it mostly dispatches the
engineer and the reviewer, runs the check and opens the PR. Running the lead on
Sonnet in Quick mode would roughly halve the lead's share. That is a candidate
for v0.4b. It is not adopted here: it changes who reviews the engineer's work,
so it needs its own eval comparison first.
