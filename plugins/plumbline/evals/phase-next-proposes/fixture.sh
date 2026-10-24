#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# Phase 01 has been signed off. What it left behind: a success metric missed, a
# waived bug, an open medium design finding, and scope deferred in the spec.
phase_template signoff.md
cat > "$P/qa-report.md" <<'QA'
# Phase 01 QA report

Verdict: PASS

## Bugs
| ID | AC ID | Severity | Status | Summary | Evidence |
| --- | --- | --- | --- | --- | --- |
| BUG-01-004 | AC-01-002 | medium | WONTFIX | Duplicate-name error only appears after Save, not while typing | qa/evidence/dup.png |
| BUG-01-006 | AC-01-005 | low | OPEN | Empty state illustration is blurry on mobile | qa/evidence/empty-390.png |
QA
python_free_edit() { awk -v sec="## $2" -v text="$3" '/^## / { s = ($0 == sec) } { print } s && /^[|] ---/ { print text; s = 0 }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
python_free_edit "$P/signoff.md" "Design findings" "| 1 | Rooms list | Admins can't tell inactive rooms apart at a glance on mobile | medium | OPEN | qa/evidence/inactive-390.png |"
python_free_edit "$P/signoff.md" "Success metrics results" "| An admin sets up 10 rooms | under 3 minutes | 4.5 minutes median in usability test | no |"
sed -i -E 's/^- \[ \]/- [x]/' "$P/signoff.md"
git add -A
git commit -qm "Phase 01 signed off"
