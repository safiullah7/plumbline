---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/security.md }
pattern: '^## Findings[^\n]*\n(?:(?!^## )[\s\S])*?^\|\s*#?\d+\s*\|[^\n]*(?:getRoom|/api/rooms/|by[ -]id|by its id|another clinic|other clinic|cross-clinic|cross-tenant|another tenant|other tenant)'
flags: mi
---
