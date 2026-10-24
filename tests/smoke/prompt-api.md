# Live smoke test, second session: an API-only Quick task with the first-run profile

You run in a fresh session started in D:\Repos\plumbline-smoke\api-fixture, an
empty folder. It is its own project (the hooks locate the project from where the
session started), with no docs/product/project.md. This is a hook and flow test of
the Plumbline plugin loaded from D:\Repos\plumbline\plugins\plumbline. Do every
step yourself unless it says to stop, and run every command in this folder.

PART A - The API fixture. Run:
git init -q -b main && git config user.name smoke && git config user.email smoke@example.com && git config core.autocrlf false && mkdir -p src test
Then write each file below with the Write tool, exactly as given: the path is on
the "=== FILE: <path> ===" line, relative to this folder, and the content runs to
the next "=== END ===" line. The code uses only Node built-ins, so nothing needs
installing; package.json lists express only so that detection sees an API.

=== FILE: package.json ===
{
  "name": "orders-api",
  "private": true,
  "dependencies": { "express": "^4.19.0" },
  "scripts": { "start": "node src/server.js" }
}
=== END ===

=== FILE: src/app.js ===
const http = require('node:http');
const orders = [{ id: 1, status: 'open' }, { id: 2, status: 'shipped' }];
const handler = (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  res.setHeader('content-type', 'application/json');
  if (req.method === 'GET' && url.pathname === '/orders') {
    const status = url.searchParams.get('status');
    const list = status ? orders.filter((o) => o.status === status) : orders;
    return res.end(JSON.stringify(list));
  }
  res.statusCode = 404;
  res.end(JSON.stringify({ error: 'not found' }));
};
module.exports = () => http.createServer(handler);
=== END ===

=== FILE: src/server.js ===
require('./app.js')().listen(process.env.PORT || 3000);
=== END ===

=== FILE: test/orders.test.js ===
const test = require('node:test');
const assert = require('node:assert');
const makeServer = require('../src/app.js');
const get = async (path) => {
  const server = makeServer();
  await new Promise((r) => server.listen(0, r));
  const res = await fetch('http://localhost:' + server.address().port + path);
  const body = await res.json();
  server.close();
  return { status: res.status, body };
};
test('lists all orders', async () => {
  const { status, body } = await get('/orders');
  assert.equal(status, 200);
  assert.equal(body.length, 2);
});
test('filters orders by status', async () => {
  const { body } = await get('/orders?status=open');
  assert.deepEqual(body.map((o) => o.id), [1]);
});
=== END ===

Then run and keep the output:
git add -A && git commit -q -m "API fixture"
R=$(mktemp -d) && git init -q --bare "$R" && git remote add origin "$R" && git push -q origin HEAD
node --test | grep -E '^# (pass|fail)'
ls docs 2>&1
bash /d/Repos/plumbline/plugins/plumbline/scripts/detect-project.sh | sed -n '/^## Surfaces/,/^$/p'
/plumbline:build can only be started by the user, so stop here and tell me
exactly: "Type: /plumbline:build make GET /orders reject an unknown query
parameter with a 400 error". When the build skill asks something, I'll pick its
recommended option; for the project profile question I'll answer "use it as is".
This is a test. When it has finished and I say "continue", run and keep the
output:
cat docs/product/project.md
git branch --list 'quick/*'
git log --oneline -n 5
git status --porcelain
ls -a .claude
ls docs/product
grep -rn "AC-[0-9]*-[0-9]*" test/
Also list every agent dispatched during this part (name and type), say whether any
screenshot, browser, accessibility or Playwright step was run or asked about, and
quote the triage block and the ac-check line as printed.

PART B - Report. Show one table: check, expected, actual, PASS or FAIL.
- fixture: `node --test` shows "# pass 2" and "# fail 0"; `ls docs` fails
  ("No such file or directory"), so there is no project.md yet
- detection: the detect-project.sh lines are exactly
  "## Surfaces", "| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |",
  "| --- | --- | --- | --- | --- | --- | --- |" and
  "| api | Express | ** | npm run start | | | node --dir . |" (one api row, no
  "(check)" mark, no other row)
- profile question: asked once, before the triage, showing that proposal;
  after "use it as is" nothing about the profile is asked again
- project.md: docs/product/project.md exists in this folder (not in the smoke
  folder's own docs/product), has one api row with no "(check)", and a line
  "Confirmed by: <name> on <today's date>"
- triage: the block shows "Size: Quick", "Folder: none", "Surfaces: api",
  "UX: no", "Docs: none", "Team: no"; its Roles line has no UX engineer; its Evidence
  line names api kinds (contract, authz, negative, transcripts)
- no UI work: no UX engineer or QA runner was dispatched, and no screenshot,
  browser, Playwright or accessibility step was run or asked about
- criteria: 1-3 criteria with IDs AC-<yymmdd>-<nn> (today's date), each
  observable through HTTP (a status code, a response body), with none about screens,
  layout or copy
- branch: exactly one branch quick/<yymmdd>-<slug> exists, and the profile
  is committed (git status --porcelain is empty)
- tests: a test in test/ has an AC-<yymmdd>-<nn> ID in its name, sends an
  unknown query parameter to /orders and expects status 400; the existing two tests
  still pass
- check: "ac-check: pass" is printed (exit 0), from a command that includes
  "--surface api" (and the criteria IDs)
- review: a code-reviewer subagent ran and its findings are reported
- hand-off: the report says the branch was pushed (the remote is a local
  folder, so no PR is possible)
- no team: the only agents were product (triage), the lead, one senior
  engineer and a code reviewer
- no folder: docs/product holds project.md and no feature folder or module
  folder; .claude/plumbline-quick no longer exists
Then show how many times each hook fired in this session:
for e in PreToolUse SubagentStart; do echo "$e $(grep -c "\"hook_event_name\":\"$e\"" /tmp/plumbline-hooks.jsonl)"; done
