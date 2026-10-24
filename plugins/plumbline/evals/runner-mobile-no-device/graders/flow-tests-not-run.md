---
type: regex
target: { source: file, path: docs/product/jobs/01-offline-notes/qa-report.md }
pattern: '^\|[ \t]*flow-tests[ \t]*\|[^|\n]*mobile-ui[^|\n]*\|[^|\n]*\|[ \t]*not run\b[^|\n]*\|?[ \t]*$'
flags: im
---
