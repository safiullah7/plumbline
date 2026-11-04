---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/security.md }
pattern: '^## Findings[^\n]*\n(?:(?!^## )[\s\S])*?^\|\s*#?\d+\s*\|[\s*]*(?:medium|low)[\s*]*\|[^|\n]*\|[\s*`]*deferred[\s*`]*\|'
flags: mi
---
