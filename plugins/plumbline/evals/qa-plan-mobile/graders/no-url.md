---
type: regex
target: { source: file, path: docs/product/jobs/01-offline-notes/test-plan.md }
pattern: 'https?://|localhost|www\.'
flags: i
match: not_contains
---
