---
type: regex
target: { source: file, path: docs/product/invoices/01-void-invoices/test-plan.md }
pattern: '(?=[\s\S]*409)(?=[\s\S]*404)(?=[\s\S]*(?:invoice_paid|paid))(?=[\s\S]*(?:malformed|invalid|empty|oversize|non-existent|nonexistent|unknown))'
flags: i
---
