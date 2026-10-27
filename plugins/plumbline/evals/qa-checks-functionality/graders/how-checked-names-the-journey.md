---
type: llm
focus: { source: file, path: docs/product/rooms/01-room-management/test-plan.md }
---

PASS if each Traceability row's "How checked" is one concrete line taken from the ux.md journeys or the criterion (for example opening Settings > Rooms as an admin and adding "Room 4", or POST /api/rooms as a receptionist), and its Type is journey, request, command or flow.
FAIL if a row's "How checked" is generic ("tested manually", "see code"), copies the criterion without saying how it would be checked, or a row is missing for an AC.
