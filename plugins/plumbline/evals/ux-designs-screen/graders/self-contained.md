---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/prototypes/rooms-list.html }
pattern: '<script[^>]+src=|<link[^>]+href=["'']?https?:'
flags: i
match: not_contains
---
