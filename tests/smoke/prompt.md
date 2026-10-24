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

PART 4 - Report. Show one table: check, expected, actual, PASS or FAIL.
- Part 1, state: CLEAN; MATCHES REMOTE; NO INSTALLED COPY; the version matches
  the branch name (branch v0.3 means version 0.3.x); show the tree hash
- Part 1, checks: "Validation passed" for the plugin and for the marketplace;
  every self-test run ends "0 failed"
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
  ESCALATED question; phase-evidence.sh prints "Evidence for the next phase" and
  exits 0
Then show how many times each hook fired:
for e in PreToolUse TaskCreated TaskCompleted TeammateIdle SessionStart SubagentStart; do echo "$e $(grep -c "\"hook_event_name\":\"$e\"" /tmp/plumbline-hooks.jsonl)"; done
For any failed row, also show the last 3 log lines for that hook, each cut to 600
characters.
