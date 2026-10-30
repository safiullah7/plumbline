#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# The dev plan is still the template; the phase also has a security.md, as
# kickoff.sh --set-security leaves it, and one more criterion: a room read by id.
phase_template dev-plan.md
sed 's/<phase>/01/g' "$FIXTURE_TEMPLATES/security/security.md" > "$P/security.md"
cat >> "$P/acceptance-criteria.md" <<'AC'
| AC-01-006 | UC-01-02 | rooms exist in clinics A and B | a user of clinic A opens a room by its id (GET /api/rooms/:id) | the room is returned; a room of clinic B answers 404 | Must |
AC
git add -A
git commit -qm "Add dev plan template, security.md and AC-01-006"
