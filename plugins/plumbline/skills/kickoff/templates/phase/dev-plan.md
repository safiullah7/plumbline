# Phase <phase> dev plan

Status: DRAFT

Owner: lead engineer. The lead changes the status to READY only after the user
approves this plan. The Plumbline hooks enforce ownership and task gates only
when it says READY.

## Team
| Teammate | Model | Workstream |
| --- | --- | --- |
| eng-api | sonnet | Example: appointment API |
| eng-web | sonnet | Example: appointment UI |

## Ownership
One row per teammate, including product, design and qa: a teammate without a row
can't write anything once this plan is READY. Globs are space-separated and
relative to the repo root.
| Teammate | Owned globs |
| --- | --- |
| eng-api | apps/api/src/example/** apps/api/test/example/** |
| eng-web | apps/web/src/features/example/** apps/web/e2e/example/** |
| product | docs/product/** |
| design | docs/product/** |
| qa | docs/product/** apps/web/e2e/qa/** |

## Contracts
Each shared type, DTO, endpoint and schema change, landed by the lead before the
engineers start. Consumers are teammate names, or "all".
| Contract | Path | Consumers |
| --- | --- | --- |

## Tasks
Every task subject starts with the AC IDs it delivers. Coordination work that
delivers no AC starts with [chore]. Complexity is HIGH or NORMAL.
### eng-api
- [AC-<phase>-001] Example task (NORMAL)

## Briefs
When this plan is READY, the lead runs make-briefs.sh, which writes
briefs/<teammate>.md for each engineer from this plan and the phase docs.
Engineers read their brief first.

## Decisions (ADR)
| Decision | Options considered | Chosen | Why |
| --- | --- | --- | --- |

## Integration order

## Risks
