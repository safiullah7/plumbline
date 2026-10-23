---
type: regex
target: { source: file, path: apps/api/rooms/rooms.test.js }
pattern: '\b(test|it|describe)\.(skip|todo)\(|\bxit\(|\{\s*(skip|todo)\s*:'
match: not_contains
---
