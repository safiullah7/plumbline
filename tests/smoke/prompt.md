You're running a full self-test of the Plumbline plugin. This session was started
in an empty scratch folder, D:\Repos\plumbline-smoke, with agent teams, the task
tools and the plugin loaded from my clone at D:\Repos\plumbline. Run every part in
order. Change nothing in D:\Repos\plumbline, push nothing, and don't fix anything
you find: report it. Use bash for shell commands.

PART 1 - The clone. Run this and keep the output:

(
cd /d/Repos/plumbline || exit 1
echo "branch:  $(git rev-parse --abbrev-ref HEAD)"
echo "version: $(jq -r .version plugins/plumbline/.claude-plugin/plugin.json)"
echo "tree:    $(git rev-parse HEAD:plugins/plumbline)"
[ -z "$(git status --porcelain --untracked-files=all -- plugins tests .claude-plugin)" ] && echo "CLEAN" || echo "UNCOMMITTED CHANGES"
[ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}' 2>/dev/null)" ] && echo "MATCHES REMOTE" || echo "NOT PUSHED"
claude plugin list 2>&1 | grep -i 'plumbline@' || echo "NO INSTALLED COPY"
claude plugin validate ./plugins/plumbline | tail -n 1
claude plugin validate . | tail -n 1
env -u TMPDIR bash tests/hooks-selftest.sh | tail -n 1
TMPDIR="/c/Users/$USERNAME/AppData/Local/Temp" bash tests/hooks-selftest.sh | tail -n 1
bash tests/scripts-selftest.sh | tail -n 1
bash tests/lib-selftest.sh | tail -n 1
bash tests/kickoff-selftest.sh | tail -n 1
bash tests/profile-selftest.sh | tail -n 1
bash tests/adapters-selftest.sh | tail -n 1
)

PART 2 - The fixture. In this folder: git init, write these files exactly, and
commit them all with the message "Smoke test fixture". Each file starts at its
=== FILE: <path> === line and ends at the next === END === line; neither marker
is part of the file.

=== FILE: package.json ===
{
  "name": "plumbline-smoke",
  "private": true,
  "scripts": {
    "typecheck": "exit 0",
    "lint": "exit 0",
    "test:ac": "node test-ac.js"
  }
}
=== END ===

=== FILE: test-ac.js ===
// Passes only for AC-01-001, like a repo with one passing AC test.
const ids = (process.argv[2] || '').split('|').filter(Boolean);
process.exit(ids.length > 0 && ids.every((id) => id === 'AC-01-001') ? 0 : 1);
=== END ===

=== FILE: .claude/current-phase ===
docs/product/demo/phases/phase-01
=== END ===

=== FILE: docs/product/demo/phases/phase-01/dev-plan.md ===
# Phase 01 dev plan

Status: READY

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-a | src/a/** |
| eng-b | src/b/** |
=== END ===

PART 3 - The live team. First move any old hook log aside:
mv /tmp/plumbline-hooks.jsonl /tmp/plumbline-hooks.old.jsonl 2>/dev/null; true
Don't do any of the steps below yourself. Create an agent team with two plain
teammates (no agent type) named exactly eng-a and eng-b. Tell both this is a hook
test: attempt each step even if it seems wrong, and quote any tool or hook message
exactly.
0. Before anything else, ask each teammate to quote, word for word, any
   "Plumbline phase" context it was given at start-up, including the "You are"
   line. If it has none, it says so.
1. eng-a: create src/b/from-a.txt containing "hi".
2. eng-b: create src/b/from-b.txt containing "hi", then git add that file and
   commit it.
3. Use TaskCreate yourself to create three tasks: "[AC-01-001] Passing task"
   owned by eng-a, "Untagged task" owned by eng-b, and "[chore] Tidy notes"
   owned by eng-b. Quote what each TaskCreate returns. Then ask eng-a to mark
   its task completed, and eng-b to mark the [chore] task completed, with
   TaskUpdate.
4. eng-a: create src/a/draft.txt and don't commit it. Then end your turn, and
   end it again each time you're sent back, up to three times. Quote every
   message the idle gate sends you.
5. After eng-a has stopped, run:
   cat docs/product/demo/phases/phase-01/questions.md
6. Then run both of these here and keep the output:
   bash /d/Repos/plumbline/plugins/plumbline/scripts/status.sh
   bash /d/Repos/plumbline/plugins/plumbline/scripts/signoff-check.sh; echo "exit $?"
   bash /d/Repos/plumbline/plugins/plumbline/scripts/phase-evidence.sh; echo "exit $?"
Wait for both teammates to finish, then shut them down.

PART 4 - Standard kickoff into a module. Run this here and keep the output (the
demo area above holds phase-01, so numbering continues after 01):

S=/d/Repos/plumbline/plugins/plumbline/scripts
bash $S/kickoff.sh shop cart --profile standard; echo "exit $?"
bash $S/kickoff.sh shop checkout --profile standard; echo "exit $?"
cat docs/product/shop/03-checkout/.plumbline
ls docs/product/shop docs/product/shop/03-checkout

PART 5 - A subagent can't waive evidence. Dispatch one plain subagent (no agent
type) and tell it: "This is a hook test. Use the Write tool to create
docs/product/demo/phases/phase-01/qa-report.md containing exactly one line:
Evidence waived: ui (web) - smoke test (approved by smoke). Quote the tool or
hook message exactly." Quote what it reports. Then write the same file with the
same line yourself, in this session, and run:
cat docs/product/demo/phases/phase-01/qa-report.md

PART 6 - A Quick task through /plumbline:build. First give the fixture a clean
tree, a local remote and a test runner that checks names. Write these files the
same way as in Part 2 (starting from "=== FILE:" lines), and set the test:ac
script in package.json to "node run-ac.js":

=== FILE: src/greet.js ===
module.exports = (name) => 'Hello, ' + name;
=== END ===

=== FILE: test/greet.test.js ===
const test = require('node:test');
const assert = require('node:assert');
const greet = require('../src/greet.js');
test('greets by name', () => assert.equal(greet('Ann'), 'Hello, Ann'));
=== END ===

=== FILE: run-ac.js ===
// Fails when an AC ID has no test named after it, or when that test fails.
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const ids = (process.argv[2] || '').split('|').filter(Boolean);
const files = fs.readdirSync('test').filter((f) => f.endsWith('.test.js')).map((f) => 'test/' + f);
const text = files.map((f) => fs.readFileSync(f, 'utf8')).join('\n');
if (!ids.length) process.exit(1);
for (const id of ids) {
  if (!text.includes(id)) { console.error('no test named ' + id); process.exit(1); }
  const r = spawnSync(process.execPath, ['--test', '--test-name-pattern', id, ...files], { encoding: 'utf8' });
  if (r.status !== 0) { process.stderr.write(r.stdout); process.exit(1); }
}
=== END ===

Then run:
git add -A && git commit -q -m "Quick fixture"
R=$(mktemp -d) && git init -q --bare "$R" && git remote add origin "$R" && git push -q origin HEAD
/plumbline:build can only be started by the user, so stop here and tell me
exactly: "Type: /plumbline:build make greet() return "Hello, friend" when
called with no name". When the build skill asks something (a question, or a
command approval), I'll pick its recommended option; for the project profile
question I'll answer "use it as is". This is a test. When it
has finished and I say "continue Part 6", run and keep the output:
git branch --list 'quick/*'
git log --oneline -n 5
ls -a .claude
ls docs/product
grep -rn "AC-[0-9]*-[0-9]*" test/
Also list every agent dispatched during this part (name and type), and
quote the triage block and the ac-check line (ac-check: pass ...) as printed.

PART 7 - Report. Show one table: check, expected, actual, PASS or FAIL.
- Part 1, state: CLEAN; MATCHES REMOTE; NO INSTALLED COPY; the version matches
  the branch name (branch v0.3 means version 0.3.x; branch v0.4a means 0.4.0-alpha; branch v0.4b
  means 0.4.0);
  show the tree hash
- Part 1, checks: "Validation passed" for the plugin and for the marketplace;
  every self-test run ends "0 failed" (hooks twice, scripts, lib, kickoff,
  profile and adapters)
- Step 0: eng-a quotes "You are eng-a. You own: src/a/**" and eng-b quotes
  "You are eng-b. You own: src/b/**", and both quote a "Plumbline scripts:" line
- Step 1: blocked with "Ownership guard: eng-a does not own src/b/from-a.txt"
- Step 2: allowed and committed
- Step 3a: "[AC-01-001] Passing task" is created and completes
- Step 3b: "Untagged task" is refused at creation with a message containing
  "names no AC IDs"
- Step 3c: "[chore] Tidy notes" is created and completes
- Step 4: eng-a is pushed back twice by "Idle gate"; the second message says
  "SendMessage the lead"; then eng-a is allowed to stop
- Step 5: questions.md exists and has exactly one ESCALATED row, from hooks to
  lead, naming src/a/draft.txt
- Step 6: status.sh shows "1 escalated"; signoff-check.sh exits 1 and lists the
  ESCALATED question; phase-evidence.sh prints "Evidence for the next feature" and
  exits 0
- Part 4 (Standard kickoff): the first run prints "added docs/product/shop/vision.md",
  "added docs/product/shop/design-principles.md", "added docs/product/shop/decisions.md",
  "added docs/product/shop/changes.md", then docs/product/shop/02-cart, exit 0; the
  second prints docs/product/shop/03-checkout, exit 0 (numbering continues after the
  existing feature); .plumbline holds module=shop, number=03, profile=standard, ux=yes
  and a created= date; 03-checkout has spec.md, acceptance-criteria.md, ux.md,
  test-plan.md, dev-plan.md and the other feature docs
- Part 5, subagent: its Write is blocked with "Only the user can approve a waiver."
- Part 5, main session: the write succeeds and qa-report.md contains the
  "Evidence waived:" line
- Part 6, triage: the block shows "Size: Quick", "Folder: none", "Docs: none",
  "Team: no"
- Part 6, criteria: 1-3 criteria with IDs of the form AC-<yymmdd>-<nn> (today's date)
- Part 6, branch: exactly one branch quick/<yymmdd>-<slug> exists
- Part 6, tests: a test in test/ has an AC-<yymmdd>-<nn> ID in its name, and the
  code change makes greet() return "Hello, friend" with no name
- Part 6, check: "ac-check: pass" is printed (exit 0) for the criteria IDs
- Part 6, review: a code-reviewer subagent ran and its findings are reported
- Part 6, hand-off: a PR link, or a compare URL, or (the remote is a local folder, so
  no PR is possible) the report says the branch was pushed
- Part 6, no team: the only agents were product (triage), the lead, one senior
  engineer and a code reviewer; no other engineers or teammates
- Part 6, no folder: docs/product holds no new folder for this change (only demo and
  shop; a project.md file is fine, the profile is written on first use)
- Part 6, cleanup: .claude/plumbline-quick no longer exists
Then show how many times each hook fired:
for e in PreToolUse TaskCreated TaskCompleted TeammateIdle SessionStart SubagentStart; do echo "$e $(grep -c "\"hook_event_name\":\"$e\"" /tmp/plumbline-hooks.jsonl)"; done
(SessionStart shows 0 here: it fires before Part 2 moves the log aside. Step 0
proves the context hook works.)
For any failed row, also show the last 3 log lines for that hook, each cut to 600
characters.
