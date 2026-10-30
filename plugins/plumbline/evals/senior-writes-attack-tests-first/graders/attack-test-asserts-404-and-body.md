---
type: regex
target: { source: file, path: apps/api/test/attack/rooms-by-id.test.js }
pattern: '(?:test|it)\(\s*[''"`]SEC-01-001(?=[\s\S]*404)(?=[\s\S]*(?:name|description|clinicId|not found))'
---
