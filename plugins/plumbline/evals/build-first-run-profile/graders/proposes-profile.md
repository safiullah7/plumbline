---
type: llm
---

The repo has no docs/product/project.md, so the first /plumbline:build must propose a project profile before anything else. There is no shell here, so the proposal comes from the manifests the skill can read (pyproject.toml, here a Python command line tool, surface cli).

PASS if the reply shows a proposed profile, with a Surfaces table (or list) that includes a cli surface, and asks the user to confirm it: use it as is, edit it, or skip it for now. The reply stops at that question.
FAIL if there is no proposed profile, if it does not ask the user to use, edit or skip it, or if the reply goes on to triage, plan or implement the --quiet flag as if the profile question did not need an answer.
