#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
git add -A
git commit -qm "Dev plan approved"
# eng-api's change: active-first sorting for the list, but it drops the clinic
# filter, so every clinic sees every room (AC-01-004).
cat > apps/api/rooms/store.js <<'EOF'
// In-memory room store for the demo app.
let rooms = [];
let next = 1;
module.exports = {
  list: ({ clinicId, includeInactive = true }) =>
    rooms
      .filter((r) => includeInactive || r.status === 'active')
      .sort((a, b) => (a.status === b.status ? a.name.localeCompare(b.name) : a.status === 'active' ? -1 : 1)),
  create: (r) => { const room = { id: String(next++), status: 'active', ...r }; rooms.push(room); return room; },
  deactivate: ({ clinicId, id }) => {
    const room = rooms.find((r) => r.id === id && r.clinicId === clinicId);
    if (room) room.status = 'inactive';
    return room;
  },
  reset: () => { rooms = []; next = 1; },
};
EOF
git diff > changes.diff
