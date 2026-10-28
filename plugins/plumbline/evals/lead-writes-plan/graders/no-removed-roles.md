---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
pattern: '^\|\s*(?:design|ux|qa-runner)[\w-]*\s*\|'
flags: mi
match: not_contains
---
