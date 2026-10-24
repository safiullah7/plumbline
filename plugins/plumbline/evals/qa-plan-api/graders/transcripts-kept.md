---
type: regex
target: { source: file, path: docs/product/invoices/01-void-invoices/test-plan.md }
pattern: 'transcripts?[\s\S]{0,200}(?:qa/|\.md|\.json|\.http|\.txt)|(?:qa/|\.md|\.json|\.http|\.txt)[\s\S]{0,200}transcripts?'
flags: i
---
