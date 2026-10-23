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
Each shared type, DTO, endpoint and schema change, and the commit that lands it.

## Tasks
### eng-api
- [AC-<phase>-001] Example task (NORMAL)

## Integration order

## Risks
