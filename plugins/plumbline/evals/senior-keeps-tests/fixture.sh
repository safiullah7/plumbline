#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
# AC tests for the rooms API. AC-01-002 fails: routes.js has no duplicate check.
cat > apps/api/rooms/rooms.test.js <<'EOF'
// Rooms API tests, named after the phase 01 acceptance criteria.
const { test } = require('node:test');
const assert = require('node:assert');
const store = require('./store');
const { createRoom } = require('./routes');

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

test('AC-01-002 a duplicate room name is rejected with 409', () => {
  store.reset();
  call(createRoom, admin, { name: 'Room 4' });
  const res = call(createRoom, admin, { name: 'room 4' });
  assert.strictEqual(res.statusCode, 409);
  assert.strictEqual(res.body.message, 'A room with this name already exists');
});

test('AC-01-003 a receptionist cannot add rooms', () => {
  store.reset();
  const res = call(createRoom, receptionist, { name: 'Room 5' });
  assert.strictEqual(res.statusCode, 403);
});
EOF
git add -A
git commit -qm "Rooms API tests"
