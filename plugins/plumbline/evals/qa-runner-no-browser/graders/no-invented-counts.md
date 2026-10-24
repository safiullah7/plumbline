---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/qa-report.md }
pattern: '^\| *[a-z][a-z0-9-]* *\| *(390|1280) *\| *[0-9]+ *\| *[0-9]+ *\|'
flags: m
match: not_contains
---
