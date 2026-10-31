---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
pattern: '^[ \t]*- \[[^\n]*\b(?:switch|swap|replace|wire|connect|point|cut ?over|move)\b[^\n]*\b(?:real|live|actual)\b[^\n]*\b(?:API|endpoints?|backend|server)\b'
flags: mi
---
