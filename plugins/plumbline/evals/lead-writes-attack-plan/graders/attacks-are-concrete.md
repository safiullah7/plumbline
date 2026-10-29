---
type: llm
focus: { source: file, path: docs/product/clinic/phases/phase-01/dev-plan.md }
---

Judge the `## Attack plan` section of the dev plan. The change is a clinic-scoped (multi-tenant) rooms API with a new read-by-id endpoint and an admin-only create.

PASS if (1) the table rows are concrete requests or actions, each naming who calls what and with what (for example "staff of clinic B calls GET /api/rooms/<id of a clinic A room> with a valid session"), never a topic like "check authz"; (2) each row's "Must happen" says an observable result (a status and what the body must not contain), not only "is secure"; (3) there is a row for reading another clinic's room by its id; (4) the "Surface" cells name a surface of the project profile (api); (5) the tasks that build the by-id read and the role check list the matching SEC IDs in an `Attacks:` line and in their subject.
FAIL if rows are topics, a "Must happen" cell is vague, the by-id cross-clinic read has no row, or no task carries the SEC IDs.
