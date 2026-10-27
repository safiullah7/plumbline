---
type: regex
target: { source: file, path: docs/product/rooms/01-room-management/test-plan.md }
pattern: '^\|\s*AC-01-\d+\s*\|[^\n]*\|\s*pass\s*\|\s*$'
flags: mi
match: not_contains
---
