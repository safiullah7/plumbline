---
type: regex
target: { source: file, path: apps/api/rooms/routes.js }
pattern: 'getRoom(?:(?!\bfunction\b|module\.exports)[\s\S])*(?:clinicId|req\.user)'
---
