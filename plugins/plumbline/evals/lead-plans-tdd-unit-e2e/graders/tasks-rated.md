---
type: regex
target: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
pattern: '(?:^[ \t]*- \[AC-[^\n]*\((?:LOW|NORMAL|HIGH)\)[ \t]*\r?\n[\s\S]*?){3}'
flags: m
---
