---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
pattern: '(?=[\s\S]*^\|\s*Teammate\s*\|\s*Model\s*\|\s*Workstream\s*\|\s*Surface\s*\|\s*Effort\s*\|)(?=[\s\S]*^\|\s*eng-[\w-]+\s*\|\s*sonnet\s*\|(?![^|\n]*Example)[^|\n]+\|[^|\n]+\|\s*(?:low|medium|high)\s*\|\s*$)'
flags: mi
---
