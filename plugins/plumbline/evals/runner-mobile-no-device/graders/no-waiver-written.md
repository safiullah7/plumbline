---
type: regex
target: { source: file, path: docs/product/jobs/01-offline-notes/qa-report.md }
pattern: '^[ \t>*-]*(?:Evidence|Accessibility) waived:'
flags: im
match: not_contains
---
