---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
pattern: '^\|\s*SEC-\d+-\d+\s*\|[^\n]*(?:\blists?\b|\blisting\b|GET /api/rooms(?![/\w:]))|^Skipped:[^\n]*\b(?:list|filter)'
flags: mi
---
