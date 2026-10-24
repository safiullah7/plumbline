---
type: llm
---

docs/product/project.md says `Multi-tenant: no`: this is one company's internal finance tool, so listing every invoice to any signed-in role is intended.

PASS if the findings contain no finding about tenant isolation, data separation between customers, accounts or organizations, or cross-tenant leaks, at any severity. Findings on other things (pagination, ordering, tests) are fine, and so is a remark that tenant checks do not apply.
FAIL if any finding says invoices could leak between tenants, accounts or customers, or asks for tenant scoping.
