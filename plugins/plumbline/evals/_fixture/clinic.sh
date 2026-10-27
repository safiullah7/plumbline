#!/usr/bin/env bash
# Shared eval fixture: a small clinic app in phase 01 ("Treatment rooms"), with
# the Plumbline docs a phase has once product has written its docs and ux.md. Cases source
# this file from their scaffold script, then add or remove what they test.
# Deliberately undecided in the docs: whether an admin may deactivate the
# clinic's last active room. A good product engineer escalates it.
#
# Usage from a case's scaffold script:
#   source "$(dirname "$0")/../_fixture/clinic.sh"
# Helpers below copy the plugin's own templates, so a case always sees the
# templates of the plugin version under test.
set -e
FIXTURE_TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/kickoff/templates" && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

# Copy a phase template into the phase folder, as kickoff would.
phase_template() { sed 's/<phase>/01/g' "$FIXTURE_TEMPLATES/phase/$1" > "$P/$1"; }

# An approved (READY) dev plan for phase 01, as the build starts.
ready_plan() {
  cat > "$P/dev-plan.md" <<'PLAN'
# Phase 01 dev plan

Status: READY

## Team
| Teammate | Model | Workstream | Surface | Effort |
| --- | --- | --- | --- | --- |
| eng-api | sonnet | Rooms API | api | high |
| eng-web | sonnet | Rooms UI | web-ui | medium |

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-api | apps/api/** |
| eng-web | apps/web/** |
| product | docs/product/** |
| qa | docs/product/** |

## Contracts
docs/product/clinic/phases/phase-01/contracts/rooms.ts, landed with the phase docs.

## Tasks
### eng-api
- [AC-01-001 AC-01-003] Create room endpoint with the admin check (NORMAL)
  Files: apps/api/rooms/routes.js, apps/api/rooms/rooms.test.js
  Red (unit): AC-01-001 an admin adds a room and it is active; AC-01-003 a receptionist cannot add rooms
  E2E: AC-01-001 POST /api/rooms as an admin returns 201 and the room appears in GET /api/rooms
  Change: createRoom checks the admin role and trims the name
  Edge cases: names of 1-60 characters only
  Check: node --test apps/api
  Done when: the unit and e2e tests for AC-01-001 and AC-01-003 pass via ac-check
- [AC-01-002] Reject duplicate room names (NORMAL)
  Files: apps/api/rooms/routes.js, apps/api/rooms/rooms.test.js
  Red (unit): AC-01-002 a duplicate room name is rejected with 409
  E2E: AC-01-002 a second POST /api/rooms with "room 4" returns 409
  Change: reject a name that matches an existing room of the clinic, ignoring case
  Edge cases: the same name in another clinic is allowed
  Check: node --test apps/api
  Done when: the unit and e2e tests for AC-01-002 pass via ac-check
- [AC-01-004] List rooms scoped to the caller's clinic (HIGH)
  Files: apps/api/rooms/routes.js, apps/api/rooms/store.js
  Red (unit): AC-01-004 only the caller's clinic rooms are listed
  E2E: AC-01-004 GET /api/rooms as clinic A never returns clinic B's rooms
  Change: filter the list by the caller's clinic
  Edge cases: a caller without a clinic gets an empty list
  Check: node --test apps/api
  Done when: the unit and e2e tests for AC-01-004 pass via ac-check
### eng-web
- [AC-01-001 AC-01-005] Rooms list and Add room dialog (NORMAL)
  Files: apps/web/rooms/**
  Red (unit): AC-01-005 the empty state shows "No rooms yet" with an Add room button
  E2E: AC-01-001 an admin adds "Room 4" in the dialog and sees it in the list as Active
  Change: build the Rooms list and the Add room dialog from ux.md
  Edge cases: typed values are never cleared on error
  Check: the web unit tests and the Playwright journey
  Done when: the unit and e2e tests for AC-01-001 and AC-01-005 pass via ac-check
PLAN
}

git init -q -b main
git config user.name eval
git config user.email eval@example.com
git config core.autocrlf false

A=docs/product/clinic
P=$A/phases/phase-01
mkdir -p "$P/contracts" .claude apps/api/rooms apps/web/rooms
echo "$P" > .claude/current-phase

# The project profile (v0.4b): an api and a web-ui surface. Clinics are tenants.
# Run, Typecheck and Lint stay empty because the demo app has no such scripts;
# an empty cell skips that check.
project_profile yes none "| api | Node | apps/api/** | | | | node --dir apps/api |
| web-ui | React | apps/web/** | | | | |"

cat > "$A/vision.md" <<'EOF'
# Clinic vision

Owner: product engineer

## Who it's for
Receptionists at busy front desks, clinic admins who set the clinic up, and
clinicians between patients. Each clinic is a separate tenant.

## Problem
Clinics track rooms, staff and appointments on paper and in spreadsheets, so
double bookings and lost changes are common.

## Product principles
- Never lose typed data.
- One clinic never sees another clinic's data.
- The receptionist's common tasks take one screen and no training.

## Phases
| Phase | Goal | Status |
| --- | --- | --- |
| phase-01 | Treatment rooms: admins manage the clinic's rooms | In progress |
| phase-02 | Room schedules: opening hours per room | Next |
EOF

cat > "$P/spec.md" <<'EOF'
# Phase 01: Treatment rooms

Owner: product engineer

## Goal
Clinic admins can set up the treatment rooms their clinic has, so later phases
can book appointments into rooms. Receptionists can see the rooms.

## Users and roles
| Role | Context | What they need from this phase |
| --- | --- | --- |
| Clinic admin | Sets the clinic up, a few times a year | Add, rename and deactivate rooms |
| Receptionist | Front desk, many times a day | See which rooms exist and which are active |

## Use cases
### UC-01-01 Add a room
Admin adds a room with a name and an optional description.
### UC-01-02 List rooms
Admin and receptionist see the clinic's rooms, active first, then inactive.
### UC-01-03 Deactivate a room
Admin deactivates a room that is closed or under repair. An inactive room can't
be booked. An admin can reactivate it.

## Business rules
- Room names are unique within a clinic, case-insensitive, 1-60 characters.
- A clinic can have at most 50 rooms, active or inactive.
- Rooms are never deleted, only deactivated.
- Not decided yet: whether an admin may deactivate the clinic's last active room.

## Data and permissions
Rooms belong to one clinic. Every query is scoped to the caller's clinic.
Only clinic admins can add, rename, deactivate or reactivate rooms.
Receptionists can only view.

## Out of scope
Booking appointments into rooms (phase 03). Room opening hours (phase 02).

## Decisions
| Decision | Options considered | Chosen | Why |
| --- | --- | --- | --- |
EOF

cat > "$P/acceptance-criteria.md" <<'EOF'
# Phase 01 acceptance criteria

Owner: product engineer. Every criterion is observable in the UI or API and states
the exact expected result. Tests are named after these IDs.

| ID | Use case | Given | When | Then | Priority |
| --- | --- | --- | --- | --- | --- |
| AC-01-001 | UC-01-01 | an admin on the Rooms page | they add a room named "Room 4" | "Room 4" appears in the list as Active | Must |
| AC-01-002 | UC-01-01 | a room named "Room 4" exists | an admin adds "room 4" | the dialog shows "A room with this name already exists" and nothing is saved | Must |
| AC-01-003 | UC-01-01 | a receptionist on the Rooms page | the page loads | there is no Add room button, and POST /api/rooms returns 403 | Must |
| AC-01-004 | UC-01-02 | clinics A and B each have rooms | a user of clinic A opens the Rooms page | only clinic A's rooms are listed | Must |
| AC-01-005 | UC-01-02 | the clinic has no rooms | an admin opens the Rooms page | the empty state says "No rooms yet" with an Add room button | Should |
EOF

cat > "$P/ux.md" <<'EOF'
# Phase 01 UX

Owner: product engineer. Engineers build the UI from this text: no prototypes,
mockups, wireframes or palette files.

## People and context
Admins set rooms up on a desktop. Receptionists glance at the list on a desktop
or tablet while talking to patients.

## Journeys
### UC-01-01 Add a room
Trigger: an admin opens Settings > Rooms and chooses Add room. They type a name
(and optionally a description) and save. The dialog closes and the new room is
in the list as Active. Unhappy paths: a name that already exists shows "A room
with this name already exists" under the field and keeps the typed values; a
receptionist never sees the Add room button.
### UC-01-02 List rooms
Trigger: any user opens Settings > Rooms. They see their clinic's rooms, active
first. An empty clinic shows "No rooms yet" (admins also get an Add room button).

## Screen inventory
| Screen | Use cases | Purpose | Entered from | Leads to |
| --- | --- | --- | --- | --- |
| Rooms list | UC-01-01, UC-01-02 | See and manage rooms | Settings > Rooms | Add room dialog |
| Add room dialog | UC-01-01 | Add a room | Rooms list | Rooms list |

## Screens
### Rooms list
- Purpose: see which rooms the clinic has.
- Layout and hierarchy: page title "Rooms" with the Add room button at the top
  right (admins only), then one row per room.
- Components: table rows with name, description and an Active/Inactive badge.
- States: empty ("No rooms yet"), loading (skeleton rows), error ("Couldn't load rooms. Retry"), success
- Responsive behaviour: rows stack on a tablet.
- Microcopy: heading "Rooms"; button "Add room".
### Add room dialog
- Purpose: add one room.
- Layout and hierarchy: modal with Name, Description, then Cancel and Save.
- States: Save is disabled until Name is valid; error under the field; typed values are never cleared on error.
- Microcopy: title "Add room"; error "A room with this name already exists".
EOF

cat > "$P/questions.md" <<'EOF'
# Phase 01 questions

Status values: OPEN, ANSWERED, ESCALATED (needs the user; blocks the item).

| # | From | To | Question | Answer | Status |
| --- | --- | --- | --- | --- | --- |
EOF

cat > "$P/contracts/rooms.ts" <<'EOF'
// Shared contract for rooms. Owned by the lead engineer.
export type RoomStatus = 'active' | 'inactive';

export interface Room {
  id: string;
  clinicId: string;
  name: string;
  description?: string;
  status: RoomStatus;
}

export interface CreateRoomRequest {
  name: string;
  description?: string;
}

export type CreateRoomResponse = Room;
EOF

cat > apps/api/rooms/routes.js <<'EOF'
// Rooms API (phase 01). Owned by eng-api.
const rooms = require('./store');

function listRooms(req, res) {
  res.json(rooms.list({ clinicId: req.user.clinicId }));
}

function createRoom(req, res) {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'forbidden' });
  const name = String(req.body.name || '').trim();
  if (name.length < 1 || name.length > 60) return res.status(400).json({ error: 'invalid name' });
  const room = rooms.create({ clinicId: req.user.clinicId, name, description: req.body.description });
  res.status(201).json(room);
}

module.exports = { listRooms, createRoom };
EOF

cat > apps/api/rooms/store.js <<'EOF'
// In-memory room store for the demo app.
let rooms = [];
let next = 1;
module.exports = {
  list: ({ clinicId }) => rooms.filter((r) => r.clinicId === clinicId),
  create: (r) => { const room = { id: String(next++), status: 'active', ...r }; rooms.push(room); return room; },
  reset: () => { rooms = []; next = 1; },
};
EOF

git add -A
git commit -qm "Phase 01 docs: spec, acceptance criteria, ux"
