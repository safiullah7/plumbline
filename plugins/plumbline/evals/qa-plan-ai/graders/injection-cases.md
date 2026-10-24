---
type: regex
target: { source: file, path: docs/product/assistant/01-ticket-summaries/test-plan.md }
pattern: '(?=[\s\S]*inject)(?=[\s\S]*system prompt)(?=[\s\S]*(?:ignore|override|disregard))'
flags: i
---
