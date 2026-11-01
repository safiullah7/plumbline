#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
# Phase 01 gets one more rule, so the brief can hold two small API tasks.
cat >> "$P/acceptance-criteria.md" <<'EOF'
| AC-01-006 | UC-01-01 | a clinic already has 50 rooms | an admin adds one more | POST /api/rooms returns 409 with the code ROOM_LIMIT_REACHED and nothing is saved | Must |
EOF
# A tiny HTTP app over the route handlers, so an API e2e test can drive real
# requests. The caller is read from the x-user header (JSON).
cat > apps/api/app.js <<'JS'
// Demo HTTP app for phase 01. The caller comes from the x-user header.
const http = require('node:http');
const { createRoom, listRooms } = require('./rooms/routes');

function createApp() {
  return http.createServer((req, res) => {
    let raw = '';
    req.on('data', (chunk) => { raw += chunk; });
    req.on('end', () => {
      const shim = {
        statusCode: 200,
        status(code) { this.statusCode = code; return this; },
        json(data) {
          res.writeHead(this.statusCode, { 'content-type': 'application/json' });
          res.end(JSON.stringify(data));
        },
      };
      const user = JSON.parse(req.headers['x-user'] || '{}');
      if (req.method === 'POST' && req.url === '/api/rooms') {
        return createRoom({ user, body: raw ? JSON.parse(raw) : {} }, shim);
      }
      if (req.method === 'GET' && req.url === '/api/rooms') return listRooms({ user }, shim);
      return shim.status(404).json({ error: 'not found' });
    });
  });
}

module.exports = { createApp };
JS
git add -A
git commit -qm "Add the demo HTTP app and AC-01-006"
