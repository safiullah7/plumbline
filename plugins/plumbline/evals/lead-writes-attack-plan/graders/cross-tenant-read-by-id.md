---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
pattern: '^\|\s*SEC-\d+-\d+\s*\|(?=[^\n]*(?:\b(?:another|other|different|second|foreign)\b|clinic [AB]\b))(?=[^\n]*(?:/api/rooms/|\bby (?:its |their |the )?id\b|\bid of\b|<id))'
flags: mi
---
