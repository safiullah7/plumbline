---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-02/spec.md }
---

decisions.md records that all times are stored and shown in the clinic's local time zone, and that per-user time zones were rejected.

PASS if the spec states that opening hours are stored and shown in the clinic's local time zone, and does not make per-user time zones a requirement (it may mention the suggestion was declined or escalated because of the recorded decision).
FAIL if the spec adopts per-user time zones or UTC display as a requirement, or says nothing about which time zone hours are in.
