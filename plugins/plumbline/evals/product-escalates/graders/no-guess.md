---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-01/acceptance-criteria.md }
---

The docs leave open whether an admin may deactivate the clinic's last active room.

PASS if no acceptance criterion decides that case (allowing it, blocking it, or warning about it), or if a criterion that mentions it is explicitly marked as pending or blocked on an escalated question.
FAIL if any criterion states a definite outcome for deactivating the last active room.
