---
type: regex
target: { source: file, path: docs/product/assistant/01-ticket-summaries/test-plan.md }
pattern: 'threshold[\s\S]{0,600}?(?:[≥>]=?\s*\d|\d+(?:\.\d+)?\s*%|0\.\d+|\d+\s*/\s*\d+)'
flags: i
---
