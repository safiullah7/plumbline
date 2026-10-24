---
type: llm
---

The diff adds POST /v1/invoices/{id}/void. The spec says only admins may void; the route is registered without auth.RequireRole(auth.Admin), so any signed-in member or viewer can void an invoice.

PASS if the findings report, at the highest severity (Critical), that the void endpoint has no role or authorization check (members and viewers can void), and give the file and a concrete fix such as wrapping the route with auth.RequireRole(auth.Admin).
FAIL if that is missed, or reported below the highest severity.
