#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
# The phase also has a security.md and the approved criterion AC-01-006.
sed 's/<phase>/01/g' "$FIXTURE_TEMPLATES/security/security.md" > "$P/security.md"
cat >> "$P/acceptance-criteria.md" <<'AC'
| AC-01-006 | UC-01-02 | rooms exist in clinics A and B | a user of clinic A opens a room by its id (GET /api/rooms/:id) | the room is returned; a room of clinic B answers 404 | Must |
AC
git add -A
git commit -qm "Add security.md and AC-01-006"
