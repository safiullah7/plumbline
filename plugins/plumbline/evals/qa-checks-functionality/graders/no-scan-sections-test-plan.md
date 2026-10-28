---
type: regex
target: { source: file, path: docs/product/rooms/01-room-management/test-plan.md }
pattern: '^#+\s*(?:Accessibility|Visual comparison|Regression)'
flags: mi
match: not_contains
---
