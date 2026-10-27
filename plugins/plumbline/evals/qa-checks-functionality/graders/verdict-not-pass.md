---
type: regex
target: { source: file, path: docs/product/rooms/01-room-management/qa-report.md }
pattern: '^Verdict:\s*PASS\b'
flags: mi
match: not_contains
---
