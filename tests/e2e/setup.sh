#!/usr/bin/env bash
# Creates the mini-phase end-to-end test repo: a tiny clinic app with no
# dependencies (plain Node http server, node:test, static HTML), plus the product
# brief the team works from. Usage:
#   bash tests/e2e/setup.sh /d/Repos/plumbline-e2e
set -eu
DIR="${1:?target folder}"
HERE="$(cd "$(dirname "${0//\\//}")" && pwd)"
rm -rf "$DIR"
mkdir -p "$DIR" && cd "$DIR"
git init -q -b main
git config core.autocrlf false
mkdir -p apps/api apps/web scripts docs

cat > package.json <<'EOF'
{
  "name": "clinic",
  "private": true,
  "scripts": {
    "typecheck": "node scripts/check-syntax.js",
    "lint": "node scripts/check-syntax.js",
    "test": "node --test",
    "test:ac": "node scripts/run-ac-tests.js",
    "start": "node apps/api/server.js"
  }
}
EOF

cat > scripts/check-syntax.js <<'EOF'
// Syntax-checks every .js file under apps/ (the app has no type checker).
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
function walk(d) {
  return fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.js') ? [path.join(d, e.name)] : []);
}
for (const f of walk('apps')) execFileSync(process.execPath, ['--check', f], { stdio: 'inherit' });
EOF

cat > scripts/run-ac-tests.js <<'EOF'
// Runs the tests named after the given AC IDs: node scripts/run-ac-tests.js "AC-01-001|AC-01-002".
// Passes only when every ID has at least one passing test named after it and none failing.
const { spawnSync } = require('node:child_process');
const ids = (process.argv[2] || '').split('|').filter(Boolean);
if (!ids.length) { console.error('ac-tests: no AC IDs given'); process.exit(1); }
const r = spawnSync(process.execPath, ['--test', '--test-reporter=tap', `--test-name-pattern=${ids.join('|')}`], { encoding: 'utf8' });
const out = (r.stdout || '').replace(/\r/g, '');
process.stdout.write(out); process.stderr.write(r.stderr || '');
const problems = [];
for (const id of ids) {
  const ok = new RegExp(`^ *ok [0-9]+ - .*${id}`, 'm').test(out);
  const bad = new RegExp(`^ *not ok [0-9]+ - .*${id}`, 'm').test(out);
  if (bad) problems.push(`${id}: failing`);
  else if (!ok) problems.push(`${id}: no test named after it`);
}
if (problems.length) { console.error('ac-tests: ' + problems.join('; ')); process.exit(1); }
EOF

cat > apps/api/server.js <<'EOF'
// Clinic API and static web server. Auth is simulated: the X-User header holds
// JSON like {"clinicId":"c1","role":"admin"}.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

function user(req) {
  try { return JSON.parse(req.headers['x-user'] || ''); } catch { return null; }
}

const routes = {}; // "METHOD /path" -> handler(req, res, user, body)

function send(res, status, data) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(data));
}

const server = http.createServer((req, res) => {
  const key = `${req.method} ${req.url.split('?')[0]}`;
  if (routes[key]) {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      const u = user(req);
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      routes[key](req, res, u, body ? JSON.parse(body) : {});
    });
    return;
  }
  const file = path.join(__dirname, '..', 'web', req.url === '/' ? 'index.html' : req.url);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200); res.end(data);
  });
});

if (require.main === module) server.listen(process.env.PORT || 3000);
module.exports = { server, routes, send };
EOF

cat > apps/web/index.html <<'EOF'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Clinic</title></head>
<body><h1>Clinic</h1><p>Settings</p></body>
</html>
EOF

cp "$HERE/brief.md" docs/brief.md
echo "# Clinic app" > README.md
git add -A
git -c user.name=e2e -c user.email=e2e@example.com commit -qm "Clinic app skeleton and product brief"
echo "Ready: $DIR"
