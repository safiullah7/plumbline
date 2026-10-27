# Phase <phase> dev plan

Status: DRAFT

Owner: lead engineer. The lead changes the status to READY only after the user
approves this plan. The Plumbline hooks enforce ownership and task gates only
when it says READY.

## Team
Surface names a row of docs/product/project.md and picks that workstream's checks
(typecheck, lint, AC tests). The lead sets each engineer's Effort from its
tasks' complexity (LOW is low, NORMAL is medium, HIGH is high) and passes it
when it dispatches or spawns the engineer.
| Teammate | Model | Workstream | Surface | Effort |
| --- | --- | --- | --- | --- |
| eng-api | sonnet | Example: appointment API | api | medium |
| eng-web | sonnet | Example: appointment UI | web-ui | medium |

## Ownership
One row per teammate, including product and qa: a teammate without a row
can't write anything once this plan is READY. Globs are space-separated and
relative to the repo root.
| Teammate | Owned globs |
| --- | --- |
| eng-api | apps/api/src/example/** apps/api/test/example/** |
| eng-web | apps/web/src/features/example/** apps/web/e2e/example/** |
| product | docs/product/** |
| qa | docs/product/** |

## Contracts
Each shared type, DTO, endpoint and schema change, landed by the lead before the
engineers start. Consumers are teammate names, or "all".
| Contract | Path | Consumers |
| --- | --- | --- |

## Tasks
Every task subject starts with the AC IDs it delivers. Coordination work that
delivers no AC starts with [chore]. Complexity is LOW, NORMAL or HIGH. The lead
writes one section per engineer, tasks in order, in this format:
### eng-api
- [AC-<phase>-001] <title> (LOW|NORMAL|HIGH)
  Files: the files to create or change
  Red (unit): the failing unit test to write first
  E2E: the e2e test for the journey
  Change: what to change
  Edge cases: what must also hold
  Check: how to check it
  Done when: the unit and e2e tests for these AC IDs pass (via ac-check)

## Briefs
When this plan is READY, the lead runs make-briefs.sh, which writes
briefs/<teammate>.md for each engineer from this plan and the phase docs.
Engineers read their brief first.

## Decisions (ADR)
| Decision | Options considered | Chosen | Why |
| --- | --- | --- | --- |

## Integration order

## Risks
