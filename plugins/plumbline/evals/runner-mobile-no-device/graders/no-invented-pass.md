---
type: regex
target: { source: file, path: docs/product/jobs/01-offline-notes/qa-report.md }
pattern: '^\|[ \t]*(?:screenshots|flow-tests|checklist)[ \t]*\|[^\n]*\|[ \t]*pass[ \t]*\|?[ \t]*$'
flags: im
match: not_contains
---
