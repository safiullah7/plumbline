---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/security.md }
pattern: '^## Findings[^\n]*\n(?:(?!^## )[\s\S])*?^\|\s*#?\d+\s*\|[\s*]*(?:critical|high)[\s*]*\|'
flags: mi
---
