---
type: regex
target: { source: file, path: docs/product/invoices/01-void-invoices/test-plan.md }
pattern: '(?=[\s\S]*\bcontract\b)(?=[\s\S]*\bauthz\b)(?=[\s\S]*\bnegative\b)(?=[\s\S]*\btranscripts\b)'
flags: i
---
