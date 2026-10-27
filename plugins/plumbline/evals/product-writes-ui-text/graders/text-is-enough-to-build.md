---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-01/ux.md }
---

An engineer will build the UI from this text alone: there are no mockups.

PASS if ux.md (1) describes each use case as a journey with its steps and at least one unhappy path (for example a duplicate room name, or a receptionist who must not see Add room), (2) lists every screen and dialog in the Screen inventory table, and (3) for each screen gives its purpose, its layout in words, every state (empty, loading, error, success) and the exact text for its headings, buttons, errors and empty state. The copy and states agree with acceptance-criteria.md.
FAIL if a screen has only template placeholders, the journeys are missing steps or unhappy paths, states are missing, copy is vague ("an error message"), or the document leans on a picture, wireframe or HTML instead of words.
