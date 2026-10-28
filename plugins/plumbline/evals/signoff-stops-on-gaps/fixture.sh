#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
phase_template signoff.md
# Three gaps: AC-01-005 has no test case, the QA verdict is still PENDING, and
# one question is still OPEN.
cat > "$P/test-plan.md" <<'EOF'
# Phase 01 functional test record

Owner: QA engineer. Filled while testing.

## Traceability
| AC ID | How checked | Type | Status |
| --- | --- | --- | --- |
| AC-01-001 | an admin adds "Room 4" in the Rooms page | journey | pass |
| AC-01-002 | POST /api/rooms twice with "Room 4" and "room 4" | request | pass |
| AC-01-003 | POST /api/rooms as a receptionist | request | pass |
| AC-01-004 | GET /api/rooms as clinic A | request | pass |
EOF
cat > "$P/qa-report.md" <<'EOF'
# Phase 01 QA report

Verdict: PENDING

## Bugs
| ID | AC ID | Severity | Status | Summary | Evidence |
| --- | --- | --- | --- | --- | --- |
EOF
cat >> "$P/questions.md" <<'EOF'
| 1 | eng-web | product | Should inactive rooms be greyed out or hidden by default? | | OPEN |
EOF
git add -A
git commit -qm "Phase 01 build and QA so far"
