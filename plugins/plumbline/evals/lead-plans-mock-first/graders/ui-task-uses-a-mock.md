---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
pattern: '^### [^\n]*(?:web|ui|front)[^\n]*\n(?:(?!^#{2,3} )[\s\S])*?(?:\bmocks?\b|\bMSW\b|\bstubs?\b|fixture server)'
flags: mi
---
