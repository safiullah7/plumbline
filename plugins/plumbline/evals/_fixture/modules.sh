#!/usr/bin/env bash
# Shared eval fixture for v0.4: the clinic app with one module, "rooms", in the
# new docs layout and one finished feature, 01-room-management. Sourcing this
# file scaffolds the repo and leaves one commit on main.
#
#   docs/product/rooms/{vision,design-principles,decisions,changes}.md
#   docs/product/rooms/01-room-management/   (slim profile, with .plumbline)
#   apps/api/rooms, apps/web/rooms, package.json
#
# Cases source it from their scaffold script, then add or remove what they test:
#   source "$(dirname "$0")/../_fixture/modules.sh"
# The docs are copied from the plugin's own templates, so a case always sees the
# templates of the plugin version under test.
set -e
FIXTURE_TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/kickoff/templates" && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

git init -q -b main
git config user.name eval
git config user.email eval@example.com
git config core.autocrlf false

M=docs/product/rooms
F=$M/01-room-management
mkdir -p "$F/contracts" "$F/briefs" "$F/prototypes" apps/api/rooms apps/web/rooms

# The project profile (v0.4b): an api and a web-ui surface. Clinics are tenants.
# Run, Typecheck and Lint stay empty because the demo app has no such scripts;
# an empty cell skips that check.
project_profile yes none "| api | Node | apps/api/** | | | | node --dir apps/api |
| web-ui | React | apps/web/** | | | | |"

# Module docs, filled in as kickoff.sh would.
for name in design-principles decisions changes; do
  sed -e 's/<Module>/Rooms/g' -e 's/<module>/rooms/g' "$FIXTURE_TEMPLATES/module/$name.md" > "$M/$name.md"
done

cat > "$M/vision.md" <<'EOF'
# Rooms vision

Owner: product engineer

## Who it's for
Clinic admins who set the clinic up, and receptionists at busy front desks who
need to see which rooms exist. Each clinic is a separate tenant.

## Problem
Clinics track treatment rooms on paper and in spreadsheets, so double bookings
and lost changes are common.

## Product principles
- Never lose typed data.
- One clinic never sees another clinic's data.
- The receptionist's common tasks take one screen and no training.

## Features
Each feature is named by the outcome it changes for a user, and picked from
evidence: open findings, bugs, metrics and questions from earlier features.
Folder: docs/product/rooms/.
| Feature | Goal | Outcome (measurable) | Why next | Status |
| --- | --- | --- | --- | --- |
| 01-room-management | Admins add and list the clinic's rooms | An admin sets up 10 rooms in under 3 minutes | First thing every clinic needs | Done |
EOF

# Feature 01: every phase template, then the standard overlay, as kickoff.sh does.
for t in "$FIXTURE_TEMPLATES"/phase/* "$FIXTURE_TEMPLATES"/standard/*; do
  sed -e 's/<phase>/01/g' -e 's/<Module>/Rooms/g' -e 's/<module>/rooms/g' "$t" > "$F/${t##*/}"
done
: > "$F/contracts/.gitkeep"; : > "$F/briefs/.gitkeep"; : > "$F/prototypes/.gitkeep"
cat > "$F/.plumbline" <<'EOF'
module=rooms
number=01
profile=standard
ux=yes
created=2026-10-01
EOF

cat > "$F/spec.md" <<'EOF'
# Feature 01: Room management

Owner: product engineer

## Goal
Clinic admins can set up the treatment rooms their clinic has, so later features
can book appointments into rooms. Receptionists can see the rooms.

## Requirements
| Priority | Requirement | Use case |
| --- | --- | --- |
| P0 | An admin adds a room with a name and an optional description | UC-01-01 |
| P0 | Admins and receptionists see the clinic's rooms | UC-01-02 |
| P1 | An empty clinic shows a helpful empty state | UC-01-02 |

## Business rules
- Room names are 1-60 characters.
- A clinic can have at most 50 rooms.
- Rooms are never deleted, only deactivated (a later feature).

## Data and permissions
Rooms belong to one clinic. Every query is scoped to the caller's clinic.
Only clinic admins can add rooms. Receptionists can only view.

## Non-Goals
Deactivating rooms and opening hours. They come in later features.

## Success metrics
| Metric | Target | Measured how, over what window |
| --- | --- | --- |
| An admin sets up 10 rooms | under 3 minutes | Usability test with 5 admins |
EOF

cat > "$F/acceptance-criteria.md" <<'EOF'
# Feature 01 acceptance criteria

Owner: product engineer. Every criterion is observable in the UI or API and states
the exact expected result. Tests are named after these IDs. Priority matches the
requirement's priority in spec.md (P0, P1, P2).

| ID | Use case | Given | When | Then | Priority |
| --- | --- | --- | --- | --- | --- |
| AC-01-001 | UC-01-01 | an admin on the Rooms page | they add a room named "Room 4" | "Room 4" appears in the list as Active | P0 |
| AC-01-002 | UC-01-01 | a receptionist on the Rooms page | the page loads | there is no Add room button, and POST /api/rooms returns 403 | P0 |
| AC-01-003 | UC-01-02 | clinics A and B each have rooms | a user of clinic A opens the Rooms page | only clinic A's rooms are listed | P0 |
| AC-01-004 | UC-01-02 | the clinic has no rooms | an admin opens the Rooms page | the empty state says "No rooms yet" with an Add room button | P1 |
EOF

cat > "$F/ux.md" <<'EOF'
# Feature 01 UX

Owner: UX engineer. Decisions between design directions: product engineer.

## Screen inventory
| Screen | Purpose | Entered from | Leads to |
| --- | --- | --- | --- |
| Rooms list | See and manage rooms | Settings > Rooms | Add room dialog |
| Add room dialog | Add a room | Rooms list | Rooms list |

## Screens
### Rooms list
- Primary action: Add room (admins only)
- States: empty ("No rooms yet"), loading (skeleton rows), error ("Couldn't load rooms. Retry"), success
- Each row: name, description
### Add room dialog
- Fields: Name (required), Description (optional). Save is disabled until Name is valid.
- Errors appear under the field; typed values are never cleared on error.
EOF

# App code.
cat > package.json <<'EOF'
{
  "name": "clinic",
  "private": true,
  "scripts": {
    "test:ac": "node --test apps/api"
  }
}
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

cat > apps/api/rooms/routes.js <<'EOF'
// Rooms API (feature 01).
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

cat > apps/api/rooms/rooms.test.js <<'EOF'
// Rooms API tests, named after the feature 01 acceptance criteria.
const { test } = require('node:test');
const assert = require('node:assert');
const store = require('./store');
const { createRoom, listRooms } = require('./routes');

function call(handler, user, body) {
  const res = { statusCode: 200, body: undefined };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (data) => { res.body = data; return res; };
  handler({ user, body }, res);
  return res;
}

const admin = { role: 'admin', clinicId: 'c1' };
const receptionist = { role: 'receptionist', clinicId: 'c1' };

test('AC-01-001 an admin adds a room and it is active', () => {
  store.reset();
  const res = call(createRoom, admin, { name: 'Room 4' });
  assert.strictEqual(res.statusCode, 201);
  assert.strictEqual(res.body.status, 'active');
});

test('AC-01-002 a receptionist cannot add rooms', () => {
  store.reset();
  const res = call(createRoom, receptionist, { name: 'Room 5' });
  assert.strictEqual(res.statusCode, 403);
});

test('AC-01-003 only the callers clinic rooms are listed', () => {
  store.reset();
  call(createRoom, admin, { name: 'Room 1' });
  call(createRoom, { role: 'admin', clinicId: 'c2' }, { name: 'Room 2' });
  const res = call(listRooms, admin, {});
  assert.strictEqual(res.body.length, 1);
  assert.strictEqual(res.body[0].name, 'Room 1');
});
EOF

cat > apps/web/rooms/RoomsList.jsx <<'EOF'
// Rooms list screen (feature 01).
export function RoomsList({ rooms, isAdmin, onAdd }) {
  if (rooms.length === 0) {
    return (
      <div>
        <p>No rooms yet</p>
        {isAdmin && <button onClick={onAdd}>Add room</button>}
      </div>
    );
  }
  return (
    <div>
      {isAdmin && <button onClick={onAdd}>Add room</button>}
      <ul>
        {rooms.map((r) => (
          <li key={r.id}>
            <strong>{r.name}</strong> {r.description}
          </li>
        ))}
      </ul>
    </div>
  );
}
EOF

git add -A
git commit -qm "Rooms module with feature 01"
