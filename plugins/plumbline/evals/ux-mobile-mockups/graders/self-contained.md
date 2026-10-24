---
type: regex
target: { source: file, path: docs/product/jobs/01-offline-notes/prototypes/job-notes.html }
pattern: '<script[^>]+src=|<link[^>]+href=["\'']?https?:'
flags: i
match: not_contains
---
