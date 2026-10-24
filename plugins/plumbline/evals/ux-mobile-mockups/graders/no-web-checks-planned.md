---
type: llm
focus: { source: file, path: docs/product/jobs/01-offline-notes/ux.md }
---

PASS if ux.md plans device-style checks for a phone app (simulator or emulator screenshots, the accessibility checklist) and does not plan to run an axe accessibility scan or the capture.mjs browser screenshot script. Saying those web steps do not apply is fine.
FAIL if ux.md plans to run axe or capture.mjs, or treats the screens as web pages checked in a browser.
