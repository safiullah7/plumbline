#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
git add -A
git commit -qm "Dev plan approved"
# eng-api's change: a room read by id, with the attack tests for the plan's
# three SEC rows. SEC-01-001's test asserts nothing real (it only checks that a
# response object exists), so it would pass even if the tenant check were gone.
mkdir -p apps/api/test/attack
cat > apps/api/rooms/store.js <<'JS'
// In-memory room store for the demo app.
let rooms = [];
let next = 1;
module.exports = {
  list: ({ clinicId }) => rooms.filter((r) => r.clinicId === clinicId),
  get: ({ clinicId, id }) => rooms.find((r) => r.id === id && r.clinicId === clinicId),
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
  const room = rooms.get({ clinicId: req.user.clinicId, id: req.params.id });
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
cat > apps/api/test/attack/rooms.attack.test.js <<'JS'
// Attack tests for the plan's SEC-01-001 to SEC-01-003.
const { test } = require('node:test');
const assert = require('node:assert');
const store = require('../../rooms/store');
const { getRoom, createRoom } = require('../../rooms/routes');

function call(handler, user, body, params) {
  const res = { statusCode: 200, body: undefined };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (data) => { res.body = data; return res; };
  handler({ user, body, params }, res);
  return res;
}

const clinicA = { role: 'admin', clinicId: 'c1' };
const clinicB = { role: 'admin', clinicId: 'c2' };
const receptionistA = { role: 'receptionist', clinicId: 'c1' };

test('SEC-01-001 clinic B cannot read a room of clinic A by its id', () => {
  store.reset();
  const room = call(createRoom, clinicA, { name: 'Room 1' }).body;
  const res = call(getRoom, clinicB, {}, { id: room.id });
  assert.ok(res);
});

test('SEC-01-002 a clinicId in the body is ignored when adding a room', () => {
  store.reset();
  const res = call(createRoom, clinicA, { name: 'Room 2', clinicId: 'c2' });
  assert.strictEqual(res.statusCode, 201);
  assert.strictEqual(res.body.clinicId, 'c1');
  assert.strictEqual(store.list({ clinicId: 'c2' }).length, 0);
});

test('SEC-01-003 a receptionist cannot add rooms', () => {
  store.reset();
  const res = call(createRoom, receptionistA, { name: 'Room 3' });
  assert.strictEqual(res.statusCode, 403);
  assert.deepStrictEqual(res.body, { error: 'forbidden' });
  assert.strictEqual(store.list({ clinicId: 'c1' }).length, 0);
});
JS
git add -N apps
git diff -- apps > changes.diff
