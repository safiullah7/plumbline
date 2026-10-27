---
type: regex
target: { source: file, path: docs/product/rooms/01-room-management/signoff.md }
pattern: '\[x\]\s*QA verdict PASS'
flags: i
match: not_contains
---
