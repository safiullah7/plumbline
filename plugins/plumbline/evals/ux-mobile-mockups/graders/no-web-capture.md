---
type: regex
target: { source: file, path: docs/product/jobs/01-offline-notes/ux.md }
pattern: 'node\s+\S*capture\.mjs|--a11y\b|axe-core|npx\s+axe'
flags: i
match: not_contains
---
