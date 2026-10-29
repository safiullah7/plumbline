---
type: regex
target: { source: file, path: apps/api/test/attack/fixtures.js }
pattern: 'clinicA[\s\S]*clinicB|clinicB[\s\S]*clinicA'
---
