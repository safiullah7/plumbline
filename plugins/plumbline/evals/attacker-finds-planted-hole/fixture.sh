#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
sed 's/<phase>/01/g' "$FIXTURE_TEMPLATES/security/security.md" > "$P/security.md"

# The planted hole: getRoom reads by id and never checks the caller's clinic.
mkdir -p apps/api/test/attack
cat > apps/api/rooms/store.js <<'JS'
// In-memory room store for the demo app.
let rooms = [];
let next = 1;
module.exports = {
  list: ({ clinicId }) => rooms.filter((r) => r.clinicId === clinicId),
  get: (id) => rooms.find((r) => r.id === id),
  create: (r) => { const room = { id: String(next++), status: 'active', ...r }; rooms.push(room); return room; },
  reset: () => { rooms = []; next = 1; },
};
JS
cat > apps/api/rooms/routes.js <<'JS'
// Rooms API (phase 01). Owned by eng-api.
const rooms = require('./store');

function listRooms(req, res) {
  res.json(rooms.list({ clinicId: req.user.clinicId }));
}

function getRoom(req, res) {
  const room = rooms.get(req.params.id);
  if (!room) return res.status(404).json({ error: 'not found' });
  res.json(room);
}

function createRoom(req, res) {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'forbidden' });
  const name = String(req.body.name || '').trim();
  if (name.length < 1 || name.length > 60) return res.status(400).json({ error: 'invalid name' });
  const room = rooms.create({ clinicId: req.user.clinicId, name, description: req.body.description });
  res.status(201).json(room);
}

module.exports = { listRooms, getRoom, createRoom };
JS
cat > apps/api/test/attack/fixtures.js <<'JS'
// Shared attack fixtures (built by the first task of the plan).
const store = require('../../rooms/store');
const { createRoom } = require('../../rooms/routes');

const clinicA = { role: 'admin', clinicId: 'c1' };
const clinicB = { role: 'admin', clinicId: 'c2' };
const receptionistA = { role: 'receptionist', clinicId: 'c1' };

function call(handler, user, body, params) {
  const res = { statusCode: 200, body: undefined };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (data) => { res.body = data; return res; };
  handler({ user, body, params }, res);
  return res;
}

function seedRoom(user, name) {
  return call(createRoom, user, { name }).body;
}

module.exports = { store, call, clinicA, clinicB, receptionistA, seedRoom };
JS
cat > apps/api/test/attack/rooms.attack.test.js <<'JS'
// Attack tests written by the authors for the plan's SEC-01-001 and SEC-01-002.
const { test } = require('node:test');
const assert = require('node:assert');
const { store, call, clinicA, clinicB, receptionistA, seedRoom } = require('./fixtures');
const { listRooms, createRoom } = require('../../rooms/routes');

test('SEC-01-001 a receptionist cannot add rooms', () => {
  store.reset();
  const res = call(createRoom, receptionistA, { name: 'Room 9' });
  assert.strictEqual(res.statusCode, 403);
  assert.strictEqual(store.list({ clinicId: 'c1' }).length, 0);
});

test('SEC-01-002 clinic B never sees the rooms of clinic A in the list', () => {
  store.reset();
  seedRoom(clinicA, 'Room 1');
  const res = call(listRooms, clinicB, {});
  assert.deepStrictEqual(res.body, []);
});
JS
cat >> "$P/dev-plan.md" <<'PLAN'

## Attack plan
Signals: authorization, tenancy
Attack surface: apps/api/rooms/** (GET /api/rooms, GET /api/rooms/:id, POST /api/rooms)
Attack fixtures: apps/api/test/attack/fixtures.js (two clinics with an admin each; a receptionist of clinic A; a call helper for the handlers) - built in task [AC-01-001 SEC-01-001]
Skipped: "write with another tenant's foreign key": rooms take no client-supplied foreign keys

| SEC ID | Surface | Attack | Must happen | Checked |
| --- | --- | --- | --- | --- |
| SEC-01-001 | api | A receptionist of clinic A calls POST /api/rooms with a valid session | 403 and no room is created | matches |
| SEC-01-002 | api | An admin of clinic B calls GET /api/rooms while clinic A has rooms | an empty list, nothing of clinic A's rooms | matches |
PLAN
git add -A
git commit -qm "Build done: rooms API with the by-id read; attack plan and security.md"
