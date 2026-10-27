# Phase <phase> QA report

Verdict: PENDING

PASS only when every AC has a passing check and no high or critical bug is open.
Bug status values: OPEN, FIXED (awaiting re-test), VERIFIED, WONTFIX (needs the
product engineer's agreement).
A check that can't be run is recorded "not run", with the reason in Location,
and the lead is told. Without results or a waiver, signoff won't pass.

## Bugs
| ID | AC ID | Severity | Status | Summary | Evidence |
| --- | --- | --- | --- | --- | --- |

## Evidence
Filled by the QA engineer, one row per required kind and surface. Kind is a
token from the evidence list for the surface. Result is pass, fail or not run.
A missing kind needs the user's waiver, which the build skill writes here.
| Kind | Surface | Location | Result |
| --- | --- | --- | --- |
