#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
phase_template signoff.md
# Three gaps: AC-01-005 has no test case, the QA verdict is still PENDING, and
# one question is still OPEN.
cat > "$P/test-plan.md" <<'EOF'
# Phase 01 test plan

Owner: QA engineer.

## Traceability
| AC ID | Test cases | Type | Status |
| --- | --- | --- | --- |
| AC-01-001 | TC-01-001 | e2e | Pass |
| AC-01-002 | TC-01-002 | api | Pass |
| AC-01-003 | TC-01-003 | api | Pass |
| AC-01-004 | TC-01-004 | api | Pass |
EOF
cat > "$P/qa-report.md" <<'EOF'
# Phase 01 QA report

Verdict: PENDING

## Bugs
| ID | AC ID | Severity | Status | Summary | Evidence |
| --- | --- | --- | --- | --- | --- |
EOF
cat >> "$P/questions.md" <<'EOF'
| 1 | eng-web | design | Should inactive rooms be greyed out or hidden by default? | | OPEN |
EOF
git add -A
git commit -qm "Phase 01 build and QA so far"
