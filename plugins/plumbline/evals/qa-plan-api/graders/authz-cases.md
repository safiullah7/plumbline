---
type: regex
target: { source: file, path: docs/product/invoices/01-void-invoices/test-plan.md }
pattern: '(?=[\s\S]*\bviewer\b)(?=[\s\S]*\bmember\b)(?=[\s\S]*(?:no token|without a token|missing token|no bearer|unauthenticated|expired))(?=[\s\S]*403)(?=[\s\S]*401)'
flags: i
---
