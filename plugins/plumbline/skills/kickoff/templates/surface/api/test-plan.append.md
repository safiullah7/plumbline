## API evidence plan
Rows the QA runner must fill in qa-report.md's Evidence table for surface api.
| Kind | What it proves | Location |
| --- | --- | --- |
| contract | Every endpoint matches the schema in contracts/ | qa/contract/ |
| authz | Each endpoint rejects missing, wrong-role and wrong-tenant callers | qa/authz/ |
| negative | Invalid input, missing fields and oversize bodies get the documented error | qa/negative/ |
| transcripts | Real request and response pairs for each happy path | qa/transcripts/ |
