#!/usr/bin/env bash
# Self-test for the shared task list scripts (v0.6): the idle gate's task check, the
# task gate's unblock message, status.sh's team line and watch-build.sh. Run from
# the repo root:
#   bash tests/tasks-selftest.sh
# Fakes Claude Code's files under a temp HOME: teams/<team>/config.json and
# tasks/<team>/<id>.json. Works in bash on macOS and Linux, and in Git Bash on Windows.
set -u
if ! command -v jq >/dev/null 2>&1; then
  echo "jq isn't installed or isn't on PATH. Install it (Windows: winget install jqlang.jq),"
  echo "open a new terminal, check 'jq --version', then run this again."
  exit 1
fi
G="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/.claude" "$T/home/.claude/teams/eng-team" "$T/home/.claude/tasks/eng-team" "$T/tmp" "$T/data"
cd "$T/repo" && git init -q && git config core.autocrlf false && git config user.email t@t && git config user.name t
P=docs/product/demo/01-x; mkdir -p "$P"; echo "$P" > .claude/current-phase
cat > "$P/dev-plan.md" <<'PLAN'
# 01-x dev plan

Status: READY

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-api | apps/api/** |
| eng-web | apps/web/** |
PLAN
mkdir -p apps/api apps/web
echo api > apps/api/a.ts; echo web > apps/web/w.ts
git add -A && git commit -q -m init
export HOME="$T/home" CLAUDE_PROJECT_DIR="$T/repo" TMPDIR="$T/tmp"
unset CLAUDE_CONFIG_DIR PLUMBLINE_TEAM
data="$T/data"; command -v cygpath >/dev/null 2>&1 && data=$(cygpath -m "$T/data")
export CLAUDE_PLUGIN_DATA="$data"
export PLUMBLINE_TYPECHECK="true" PLUMBLINE_LINT="true"
export PLUMBLINE_TEST_AC='f(){ [ "$1" = "AC-01-001" ]; }; f'
CFG="$T/home/.claude/teams/eng-team/config.json"
TD="$T/home/.claude/tasks/eng-team"
cwd="$T/repo"; command -v cygpath >/dev/null 2>&1 && cwd=$(cygpath -m "$T/repo")
jq -n --arg c "$cwd" '{createdAt: 1, members: [
  {name: "team-lead", agentType: "team-lead", cwd: $c}, {name: "lead", cwd: $c},
  {name: "eng-api", cwd: $c}, {name: "eng-web", cwd: $c}]}' > "$CFG"

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
assert() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}

# A task file like Claude Code writes it: put <id> <owner|-> <status> <blockedBy ids, comma-joined|-> <subject>
put() {
  jq -n --arg id "$1" --arg o "$2" --arg st "$3" --arg b "$4" --arg s "$5" \
    '{id: $id, subject: $s, description: "d", status: $st, blocks: [], blockedBy: (if $b == "-" then [] else ($b | split(",")) end)}
     + (if $o == "-" then {} else {owner: $o} end)' > "$TD/$1.json"
}
clear_tasks() { rm -f "$TD"/*.json; : > "$TD/.lock"; echo 9 > "$TD/.highwatermark"; }

# run <script> <json> [stdin-less]: sets RC, OUT (stdout) and ERR (stderr).
run() {
  local e; e=$(mktemp "$T/err.XXXXXX")
  OUT=$(echo "$2" | bash "$G/$1" 2>"$e"); RC=$?
  ERR=$(cat "$e"); rm -f "$e"
}
idle() { jq -nc --arg n "$1" --arg s "${2:-s1}" --arg t "${3-eng-team}" '{session_id: $s, teammate_name: $n} + (if $t == "" then {} else {team_name: $t} end)'; }
idle_is() { # name, session, expected exit, [text the stderr must contain], [team]
  run teammate-idle-gate.sh "$(idle "$1" "$2" "${5-eng-team}")"
  if [[ $RC -ne $3 ]]; then fail "$LABEL (expected $3, got $RC: $ERR$OUT)"
  elif [[ -n "${4:-}" && "$ERR" != *"$4"* ]]; then fail "$LABEL (stderr lacks: $4; got: $ERR)"
  else ok "$LABEL"; fi
}
Q="$P/questions.md"

# --- Idle gate: engineers ---
clear_tasks
put 1 eng-api pending - "[AC-01-001] B1: Order list"
LABEL="idle: a ready task keeps a clean engineer working"; idle_is eng-api a1 2 "[AC-01-001] B1: Order list"
LABEL="idle: the message tells it how to claim"; idle_is eng-api a2 2 "TaskUpdate in_progress"
LABEL="idle: another owner's ready task doesn't hold eng-web"; idle_is eng-web a3 0
put 2 eng-web pending 1 "[AC-01-002] B2: Order screen"
LABEL="idle: a task blocked by an open task is not ready"; idle_is eng-web a4 0
put 1 eng-api in_progress - "[AC-01-001] B1: Order list"
LABEL="idle: still blocked while the blocker is in progress"; idle_is eng-web a5 0
LABEL="idle: an in-progress task keeps its owner working"; idle_is eng-api a6 2 "B1: Order list"
put 1 eng-api completed - "[AC-01-001] B1: Order list"
LABEL="idle: a completed blocker makes the task ready"; idle_is eng-web a7 2 "B2: Order screen"
LABEL="idle: nothing left for the finished owner"; idle_is eng-api a8 0
put 2 eng-web pending 99 "[AC-01-002] B2: Order screen"
LABEL="idle: a blocker with no file counts as completed"; idle_is eng-web a9 2 "B2: Order screen"
put 2 eng-web pending "1,99" "[AC-01-002] B2: Order screen"
LABEL="idle: all blockers completed or missing"; idle_is eng-web a10 2 "B2: Order screen"
put 3 eng-web pending 2 "[AC-01-003] B3: Order detail"
put 2 eng-web completed 99 "[AC-01-002] B2: Order screen"
echo '{ not json' > "$TD/7.json"
LABEL="idle: a broken task file is skipped, the rest still count"; idle_is eng-web a11 2 "B3: Order detail"
rm -f "$TD/7.json"
put 3 eng-web completed - "[AC-01-003] B3: Order detail"
LABEL="idle: all tasks completed, exit 0"; idle_is eng-web a12 0
ls "$data/plumbline-idle" 2>/dev/null | grep -q 'a12-eng-web.tasks' && fail "idle: no state file left when nothing is ready" || ok "idle: no state file left when nothing is ready"

# No team_name, no task folder, nothing readable: the old behaviour (clean tree, exit 0).
put 4 eng-api pending - "[AC-01-004] B4: Ready"
LABEL="idle: no team_name in the payload, old behaviour"; idle_is eng-api b1 0 "" ""
LABEL="idle: a team without a task folder, old behaviour"; idle_is eng-api b2 0 "" no-such-team
clear_tasks; echo '{ not json' > "$TD/1.json"; echo 'also [ bad' > "$TD/2.json"
LABEL="idle: only unreadable task files, old behaviour"; idle_is eng-api b3 0
clear_tasks
LABEL="idle: an empty task folder, old behaviour"; idle_is eng-api b4 0
# The old dirty-files path is untouched: with a team and no tasks, it nudges twice then gives up.
echo x > apps/api/new.ts
LABEL="idle: dirty files, team without tasks, 1st push"; idle_is eng-api b5 2 "uncommitted changes in files you own"
LABEL="idle: dirty files, 2nd push"; idle_is eng-api b5 2 "SendMessage the lead"
LABEL="idle: dirty files, gives up"; idle_is eng-api b5 0
assert "idle: the dirty give-up keeps the old escalation text" grep -q 'stopped after two reminders with uncommitted changes in files it owns: apps/api/new.ts. Commit them or decide who should. (idle-gate' "$Q"
rm -f apps/api/new.ts "$Q"

# Refusals up to six for the same tasks at the same commit, then exit 0. No ESCALATED
# row, and an exit-2 refusal prints nothing on stdout (the harness ignores it there).
put 5 eng-api pending - "[AC-01-005] B5: Status changes"
codes=""; for i in 1 2 3 4 5 6 7 8; do
  run teammate-idle-gate.sh "$(idle eng-api c1)"; codes+="$RC "
  case $i in
    1|2|3) [[ $RC -eq 2 && "$ERR" == *"B5: Status changes"* ]] || fail "idle: reminder $i names the task" ;;
    4|5|6) [[ $RC -eq 2 && -z "$OUT" && "$ERR" == *"B5: Status changes"* ]] && ok "idle: refusal $i prints nothing on stdout, the text on stderr" || fail "idle: refusal $i ($RC out: $OUT err: $ERR)" ;;
  esac
done
[[ "$codes" == "2 2 2 2 2 2 0 0 " ]] && ok "idle: refusals up to 6, then exit 0" || fail "idle: refusals up to 6, then exit 0 (got: $codes)"
assert "idle: a task stall writes no ESCALATED row" test ! -e "$Q"
run teammate-idle-gate.sh "$(idle eng-api c1)"
[[ $RC -eq 0 && "$OUT" == *systemMessage* ]] && ok "idle: after the valve opens the user still sees the systemMessage" || fail "idle: valve systemMessage ($RC $OUT)"
# A new set of open tasks starts a new count.
put 6 eng-api pending - "[AC-01-006] B6: Refunds"
LABEL="idle: a different set of open tasks starts counting again"; idle_is eng-api c1 2 "B6: Refunds"
read -r _ cnt < "$data/plumbline-idle/c1-eng-api.tasks"; [[ "$cnt" == 1 ]] && ok "idle: the count restarted at 1" || fail "idle: the count restarted at 1 (got $cnt)"
# A new commit is progress: the same open tasks count from 1 again.
LABEL="idle: same tasks, 2nd refusal"; idle_is eng-api c1 2 "B6: Refunds"
read -r _ cnt < "$data/plumbline-idle/c1-eng-api.tasks"; [[ "$cnt" == 2 ]] && ok "idle: the count is 2 at the same commit" || fail "idle: the count is 2 at the same commit (got $cnt)"
git commit -q --allow-empty -m "progress"
LABEL="idle: same tasks after a new commit, still refused"; idle_is eng-api c1 2 "B6: Refunds"
read -r _ cnt < "$data/plumbline-idle/c1-eng-api.tasks"; [[ "$cnt" == 1 ]] && ok "idle: a new commit restarts the count" || fail "idle: a new commit restarts the count (got $cnt)"
rm -f "$Q"
# The text depends on the state: in progress says continue, pending says claim and how to wait.
clear_tasks; put 5 eng-api in_progress - "[AC-01-005] B5: Status changes"
run teammate-idle-gate.sh "$(idle eng-api c2)"
[[ $RC -eq 2 && "$ERR" == *"Idle gate: you have [AC-01-005] B5: Status changes in progress. Continue it now; if it is done, run its check and TaskUpdate it completed."* && "$ERR" != *"Claim it"* ]] \
  && ok "idle: an in-progress task gets the continue text" || fail "idle: in-progress text ($RC $ERR)"
put 5 eng-api pending - "[AC-01-005] B5: Status changes"
run teammate-idle-gate.sh "$(idle eng-api c3)"
[[ $RC -eq 2 && "$ERR" == *"Claim it (TaskUpdate in_progress) and start it now, red tests first. Never stop after a report."* \
   && "$ERR" == *'If you must wait for an answer, unassign it (TaskUpdate owner "") and SendMessage lead naming what you need; the lead gives it back with the answer.'* \
   && "$ERR" != *"in progress. Continue"* ]] && ok "idle: a ready pending task gets the claim text and the unassign advice" || fail "idle: pending text ($RC $ERR)"
put 5 eng-api pending - "[AC-01-005] B5: Status changes"; put 6 eng-api in_progress - "[AC-01-006] B6: Refunds"
run teammate-idle-gate.sh "$(idle eng-api c4)"
[[ "$ERR" == *"B6: Refunds in progress. Continue it now"* && "$ERR" == *"tasks ready: [AC-01-005] B5: Status changes."* ]] \
  && ok "idle: one in progress and one pending get both texts" || fail "idle: both texts ($ERR)"
clear_tasks
echo '{"id":"5","subject":"[AC-01-005] B5: Status changes","status":"pending","blockedBy":[],"owner":""}' > "$TD/5.json"
LABEL="idle: an unassigned task is not counted"; idle_is eng-api c5 0

# The task count and the dirty-files count are separate, and dirty files come first.
clear_tasks; put 5 eng-api pending - "[AC-01-005] B5: Status changes"
LABEL="idle: separate counts, task reminder 1"; idle_is eng-api d1 2 "B5: Status changes"
LABEL="idle: separate counts, task reminder 2"; idle_is eng-api d1 2 "B5: Status changes"
echo x > apps/api/dirty.ts
LABEL="idle: dirty files take priority over ready tasks"; idle_is eng-api d1 2 "uncommitted changes in files you own"
assert "idle: the dirty count has its own state file" test -f "$data/plumbline-idle/d1-eng-api"
assert "idle: the task count is untouched by the dirty push" grep -q ' 2$' "$data/plumbline-idle/d1-eng-api.tasks"
rm -f apps/api/dirty.ts
LABEL="idle: back to tasks, reminder 3 (the count wasn't reset)"; idle_is eng-api d1 2 "B5: Status changes"
assert "idle: the clean tree removed the dirty state" test ! -e "$data/plumbline-idle/d1-eng-api"
assert "idle: the task count went on to 3" grep -q ' 3$' "$data/plumbline-idle/d1-eng-api.tasks"

# --- Idle gate: the lead ---
clear_tasks
put 1 lead pending - "[chore] Land contracts"
put 2 eng-web pending - "[AC-01-002] B2: Order screen"
LABEL="lead: no nudge for its own chores alone"; idle_is lead l0 0 "" ""
LABEL="lead: an engineer's ready task with nothing in progress"; idle_is lead l1 2 "ready tasks with nobody working: eng-web B2"
LABEL="lead: the message says what to do"; idle_is lead l2 2 "SendMessage the owner to start it, or reassign."
LABEL="lead: no team_name, old behaviour"; idle_is lead l3 0 "" ""
put 3 eng-api pending - "[AC-01-003] C3: Totals"
LABEL="lead: names every waiting owner"; idle_is lead l4 2 "eng-api C3"
put 4 eng-web in_progress - "[AC-01-004] B4: Other"
LABEL="lead: an in-progress task means someone is working"; idle_is lead l5 2 "eng-api C3"
put 3 eng-api in_progress - "[AC-01-003] C3: Totals"
LABEL="lead: every engineer working, may idle"; idle_is lead l6 0
put 3 eng-api pending 4 "[AC-01-003] C3: Totals"
put 4 eng-web completed - "[AC-01-004] B4: Other"
put 2 eng-web completed - "[AC-01-002] B2: Order screen"
LABEL="lead: a task freed by a completed blocker counts"; idle_is lead l7 2 "eng-api C3"
clear_tasks; put 1 eng-api pending - "No label here"
LABEL="lead: a subject without a label is named whole"; idle_is lead l8 2 "eng-api No label here"
codes=""; for i in 1 2 3 4 5 6 7; do
  run teammate-idle-gate.sh "$(idle lead l9)"; codes+="$RC "
  [[ $i -eq 4 && $RC -eq 2 && -z "$OUT" && "$ERR" == *"eng-api No label here"* ]] && ok "lead: the 4th refusal prints nothing on stdout"
  [[ $i -eq 7 && $RC -eq 0 && "$OUT" == *systemMessage* ]] && ok "lead: the exit-0 valve carries the systemMessage"
done
[[ "$codes" == "2 2 2 2 2 2 0 " ]] && ok "lead: refusals up to 6, then exit 0" || fail "lead: caps (got: $codes)"
# Setup: tasks owned by engineers who aren't on the team yet don't hold the lead.
clear_tasks; put 1 eng-ui pending - "[AC-01-001] U1: Shell"; put 2 eng-api pending - "[AC-01-002] A2: Api"
LABEL="lead: an owner who isn't a team member is not waiting, the member still is"; idle_is lead l11 2 "ready tasks with nobody working: eng-api A2"
clear_tasks; put 1 eng-ui pending - "[AC-01-001] U1: Shell"; put 2 eng-db pending - "[AC-01-002] D1: Schema"
LABEL="lead: setup with no engineer spawned yet, may idle"; idle_is lead l12 0
LABEL="lead: ...the state file is gone"; test ! -e "$data/plumbline-idle/l12-lead.lead" && ok "$LABEL" || fail "$LABEL"
mkdir -p "$T/home/.claude/tasks/no-config-team"
echo '{"id":"1","subject":"[AC-01-001] B1: x","owner":"eng-api","status":"pending","blockedBy":[]}' > "$T/home/.claude/tasks/no-config-team/1.json"
LABEL="lead: a team with a task folder but no config file counts nobody"; idle_is lead l13 0 "" no-config-team
rm -rf "$T/home/.claude/tasks/no-config-team"
assert "lead: its state is its own file" test -f "$data/plumbline-idle/l9-lead.lead"
clear_tasks; put 1 eng-api pending - "[AC-01-001] B1: x"
LABEL="lead: with no Ownership row and no team, exit 0"; idle_is lead l10 0 "" no-such-team

# --- Task gate: the unblock message ---
tc() { jq -nc --arg id "$1" --arg who "${2:-eng-api}" --arg s "${3:-[AC-01-001] x}" --arg t "${4-eng-team}" \
  '{task_id: $id, task_subject: $s, teammate_name: $who} + (if $t == "" then {} else {team_name: $t} end)'; }
clear_tasks
put 1 eng-api in_progress - "[AC-01-001] B1: Order API"
put 2 eng-web pending 1 "[AC-01-002] B2: Order screen"
put 3 eng-web pending "1,4" "[AC-01-003] B3: Needs more"
put 4 eng-api pending - "[AC-01-004] B4: Other API"
put 5 eng-api pending 1 "[AC-01-005] B5: My own next"
run task-completed-gate.sh "$(tc 1)"
[[ $RC -eq 0 && "$OUT" == *"You unblocked eng-web's [AC-01-002] B2: Order screen: SendMessage eng-web now."* ]] \
  && ok "task gate: names the unblocked owner and task" || fail "task gate: unblock message (rc $RC: $OUT)"
[[ "$OUT" != *"B3"* ]] && ok "task gate: a task with another open blocker isn't named" || fail "task gate: B3 is still blocked"
[[ "$OUT" != *"eng-api's"* ]] && ok "task gate: the finisher isn't told about its own next task" || fail "task gate: self message"
assert "task gate: the message is a JSON systemMessage" jq -e '.systemMessage | startswith("You unblocked")' <<<"$OUT"
put 6 eng-web pending 1 "[AC-01-006] B6: Order detail"
put 7 eng-ui pending 1 "[AC-01-007] U1: Shell"
run task-completed-gate.sh "$(tc 1)"
[[ "$OUT" == *"eng-web's [AC-01-002] B2: Order screen, [AC-01-006] B6: Order detail: SendMessage eng-web now. You unblocked eng-ui's [AC-01-007] U1: Shell: SendMessage eng-ui now."* ]] \
  && ok "task gate: one sentence per owner, tasks of an owner joined" || fail "task gate: joined message ($OUT)"
run task-completed-gate.sh "$(tc 1 eng-api '[AC-01-001] x' '')"
[[ $RC -eq 0 && -z "$OUT" ]] && ok "task gate: no team_name, no message" || fail "task gate: no team_name ($RC $OUT)"
run task-completed-gate.sh "$(tc 1 eng-api '[AC-01-001] x' no-such-team)"
[[ $RC -eq 0 && -z "$OUT" ]] && ok "task gate: no task folder, no message" || fail "task gate: no task folder ($RC $OUT)"
run task-completed-gate.sh "$(tc 4 eng-api '[AC-01-001] x')"
[[ $RC -eq 0 && -z "$OUT" ]] && ok "task gate: completing a task nobody waits on prints nothing" || fail "task gate: nothing to say ($RC $OUT)"
run task-completed-gate.sh "$(tc 1 eng-api '[AC-01-002] x')"
[[ $RC -eq 2 && -z "$OUT" ]] && ok "task gate: a failing task prints no unblock message" || fail "task gate: failing task ($RC $OUT)"
run task-completed-gate.sh "$(tc 1 eng-api '[chore] Land contracts')"
[[ $RC -eq 0 && "$OUT" == *"You unblocked eng-web"* ]] && ok "task gate: a [chore] unblocks too" || fail "task gate: chore ($RC $OUT)"
# A plan with a Team table: the lead has no row, so its chores skip the checks.
cp "$P/dev-plan.md" "$T/plan.bak"
printf '\n## Team\n| Teammate | Model | Workstream | Surface |\n| --- | --- | --- | --- |\n| eng-api | sonnet | API | |\n| eng-web | sonnet | Web | |\n' >> "$P/dev-plan.md"
PLUMBLINE_TYPECHECK=false PLUMBLINE_LINT=false run task-completed-gate.sh "$(tc 1 lead 'Land contracts')"
[[ $RC -eq 0 && "$OUT" == *"You unblocked eng-web"* ]] && ok "task gate: the lead's task (no Team row) skips the checks, even with no IDs" || fail "task gate: lead chore ($RC $OUT $ERR)"
PLUMBLINE_TYPECHECK=false PLUMBLINE_LINT=false run task-completed-gate.sh "$(tc 1 lead '[chore] L0: Land contracts')"
[[ $RC -eq 0 ]] && ok "task gate: ...a [chore] L0 with failing typecheck and lint passes for the lead" || fail "task gate: lead L0 ($RC $ERR)"
PLUMBLINE_TYPECHECK=false PLUMBLINE_LINT=false run task-completed-gate.sh "$(tc 1 eng-api 'Land contracts')"
[[ $RC -eq 2 && "$ERR" == *"no AC IDs"* ]] && ok "task gate: an engineer with a Team row is still checked" || fail "task gate: engineer ($RC $ERR)"
cp "$T/plan.bak" "$P/dev-plan.md"

# --- status.sh ---
status() { (cd "$T/repo" && bash "$G/status.sh" 2>&1); }
clear_tasks
put 1 eng-api pending - "[AC-01-001] A1: one"
put 2 eng-api pending 1 "[AC-01-002] A2: two"
put 3 eng-api completed - "[AC-01-003] A3: done"
put 4 eng-web pending 2 "[AC-01-004] W1: x"
put 5 eng-web pending 2 "[AC-01-005] W2: x"
put 6 eng-web pending 2 "[AC-01-006] W3: x"
for i in 7 8 9; do put $i lead pending - "[chore] chore $i"; done
put 10 lead in_progress - "[chore] chore 10"
out=$(status)
assert "status: team line from the task list" grep -qxF "team: eng-api 2 open (1 ready) · eng-web 3 open · lead 4 chores" <<<"$out"
put 1 eng-api completed - "[AC-01-001] A1: one"
assert "status: a ready count follows the blockers" grep -qxF "team: eng-api 1 open (1 ready) · eng-web 3 open · lead 4 chores" <<<"$(status)"
for i in 1 2 3; do put $i eng-api completed - "t$i"; done
for i in 4 5 6; do put $i eng-web completed - "t$i"; done
for i in 7 8 9 10; do put $i lead completed - "t$i"; done
assert "status: every task done" grep -qxF "team: every task done (10 tasks)" <<<"$(status)"
TD_HOLD="$T/home/.claude/tasks-hold"; mv "$T/home/.claude/tasks" "$TD_HOLD"
out=$(status)
assert "status: no team line without a task folder" test -z "$(grep '^team:' <<<"$out")"
assert "status: the rest of the output is still there" grep -q '^Uncommitted files: none' <<<"$out"
mv "$TD_HOLD" "$T/home/.claude/tasks"
# Team lookup: a newer team of another project is skipped; PLUMBLINE_TEAM wins.
mkdir -p "$T/home/.claude/teams/other-team" "$T/home/.claude/tasks/other-team"
jq -n '{members: [{name: "x", cwd: "/somewhere/else"}]}' > "$T/home/.claude/teams/other-team/config.json"
put 1 eng-api pending - "[AC-01-001] A1: one"
echo '{"id":"1","subject":"other","owner":"zed","status":"pending","blockedBy":[]}' > "$T/home/.claude/tasks/other-team/1.json"
touch -d "1 minute ago" "$CFG"; touch "$T/home/.claude/teams/other-team/config.json"
assert "status: a newer team of another project is skipped" grep -q '^team: eng-api 1 open (1 ready)' <<<"$(status)"
assert "status: PLUMBLINE_TEAM picks the team" grep -qxF "team: zed 1 open (1 ready)" <<<"$(PLUMBLINE_TEAM=other-team status)"
touch -d "1 minute ago" "$CFG"
jq -n --arg c "$cwd/apps/web" '{members: [{name: "x", cwd: $c}]}' > "$T/home/.claude/teams/other-team/config.json"
touch "$T/home/.claude/teams/other-team/config.json"
assert "status: a member cwd inside the project matches, newest wins" grep -qxF "team: zed 1 open (1 ready)" <<<"$(status)"
rm -rf "$T/home/.claude/teams/other-team" "$T/home/.claude/tasks/other-team"
# Teams older than 24 hours and finished teams are passed over.
lib_call() { (cd "$T/repo" && bash -c 'source "$1/lib.sh"; shift; "$@"' _ "$G" "$@" 2>&1); }
mk_team() { # name, createdAt (ms epoch), tasks status, age for the config's mtime (touch -d)
  mkdir -p "$T/home/.claude/teams/$1" "$T/home/.claude/tasks/$1"
  jq -n --arg c "$cwd" --argjson at "$2" '{createdAt: $at, members: [{name: "lead", cwd: $c}]}' > "$T/home/.claude/teams/$1/config.json"
  echo "{\"id\":\"1\",\"subject\":\"[AC-01-001] x\",\"owner\":\"eng-api\",\"status\":\"$3\",\"blockedBy\":[]}" > "$T/home/.claude/tasks/$1/1.json"
  touch -d "$4" "$T/home/.claude/teams/$1/config.json"
}
nowms=$(( $(date +%s) * 1000 ))
touch -d "3 days ago" "$CFG"
assert "team_for_project: a config over 24 hours old (createdAt and mtime) is ignored" test -z "$(lib_call team_for_project)"
mk_team fresh-team "$nowms" pending "3 days ago"
assert "team_for_project: a recent createdAt keeps a team even when the file is old" grep -qx fresh-team <<<"$(lib_call team_for_project)"
mk_team fresh-team 1 pending "1 hour ago"
assert "team_for_project: a recent file keeps a team even with an old createdAt" grep -qx fresh-team <<<"$(lib_call team_for_project)"
rm -rf "$T/home/.claude/teams/fresh-team" "$T/home/.claude/tasks/fresh-team"
touch "$CFG"; clear_tasks; put 1 eng-api pending - "[AC-01-001] A1: x"
mk_team done-team "$nowms" completed "1 minute ago"
touch -d "5 minutes ago" "$CFG"
assert "team_for_project: a newer finished team loses to an older team still at work" grep -qx eng-team <<<"$(lib_call team_for_project)"
mk_team live-team "$nowms" pending "2 minutes ago"
assert "team_for_project: of several teams at work the newest wins" grep -qx live-team <<<"$(lib_call team_for_project)"
rm -rf "$T/home/.claude/teams/live-team" "$T/home/.claude/tasks/live-team"
put 1 eng-api completed - "[AC-01-001] A1: x"
assert "team_for_project: with only finished teams the newest finished one answers" grep -qx done-team <<<"$(lib_call team_for_project)"
assert "team_for_project: PLUMBLINE_TEAM still overrides" grep -qx eng-team <<<"$(PLUMBLINE_TEAM=eng-team lib_call team_for_project)"
rm -rf "$T/home/.claude/teams/done-team" "$T/home/.claude/tasks/done-team" "$T/home/.claude/teams/fresh-team" "$T/home/.claude/tasks/fresh-team"
touch "$CFG"
# A torn task file doesn't repeat the rows of the others.
clear_tasks; put 1 eng-api pending - "[AC-01-001] A1: x"; put 2 eng-api pending - "[AC-01-002] A2: y"; echo '{ "id": "3", "sub' > "$TD/3.json"
assert "team_tasks: a torn file adds nothing and repeats nothing" test "$(lib_call team_tasks "$TD" | cut -f1 | paste -sd' ' -)" = "1 2"
clear_tasks

# --- watch-build.sh ---
watch() { (cd "$T/repo" && bash "$G/watch-build.sh" "$@" 2>&1); }
old=$(( $(date +%s) - 7200 ))
clear_tasks
put 1 eng-api pending - "[AC-01-001] A1: Orders API"
put 2 eng-web in_progress - "[AC-01-002] W1: Orders screen"
put 3 lead pending - "[chore] Review"
for f in "$TD"/1.json "$TD"/2.json "$TD"/3.json apps/api/a.ts apps/web/w.ts; do touch -d "@$old" "$f"; done
# eng-api's last commit is 2 hours old; eng-web commits just now.
echo api2 > apps/api/a.ts; git add apps/api/a.ts
GIT_AUTHOR_DATE="@$old +0000" GIT_COMMITTER_DATE="@$old +0000" git commit -q -m "api old" -- apps/api/a.ts
touch -d "@$old" apps/api/a.ts
# The lead's last commit under docs/product is 2 hours old too.
echo old >> "$P/progress.md"; git add "$P/progress.md"
GIT_AUTHOR_DATE="@$old +0000" GIT_COMMITTER_DATE="@$old +0000" git commit -q -m "docs old" -- "$P/progress.md"
echo web2 > apps/web/w.ts; git add apps/web/w.ts; git commit -q -m "web fresh" -- apps/web/w.ts
out=$(watch --sleep 0)
assert "watch: a ready task and no activity for 10 minutes is STALLED" grep -qxF "STALLED: eng-api ([AC-01-001] A1: Orders API)" <<<"$out"
assert "watch: a fresh commit is no stall" test -z "$(grep '^STALLED: eng-web' <<<"$out")"
assert "watch: one line per teammate, none for team-lead" test "$(grep -c '^eng-' <<<"$out")" = 2 -a -z "$(grep '^team-lead' <<<"$out")"
assert "watch: the line shows the in-progress task" grep -q '^eng-web: .*in progress: \[AC-01-002\] W1: Orders screen' <<<"$out"
assert "watch: the line shows the ready task" grep -q '^eng-api: ready: \[AC-01-001\] A1: Orders API' <<<"$out"
assert "watch: not done while tasks are open" test -z "$(grep '^DONE' <<<"$out")"
out=$(watch --sleep 0 --stall-minutes 300)
assert "watch: --stall-minutes moves the threshold" test -z "$(grep '^STALLED' <<<"$out")"
echo x > apps/api/wip.ts
out=$(watch --sleep 0)
assert "watch: uncommitted owned files are counted" grep -q '^eng-api: .*uncommitted 1' <<<"$out"
assert "watch: a new file counts as activity" test -z "$(grep '^STALLED: eng-api' <<<"$out")"
rm -f apps/api/wip.ts
touch "$TD/1.json"
assert "watch: a touched task file counts as activity" test -z "$(grep '^STALLED: eng-api' <<<"$(watch --sleep 0)")"
touch -d "@$old" "$TD/1.json"
put 2 eng-web completed - "[AC-01-002] W1: Orders screen"; touch -d "@$old" "$TD/2.json"
out=$(watch --sleep 0)
assert "watch: a stalled owner is still named when others are done" grep -q '^STALLED: eng-api' <<<"$out"
assert "watch: the lead is not flagged while engineer tasks are open" test -z "$(grep -E '^(STALLED: lead|LEAD:)' <<<"$out")"
put 1 eng-api completed - "[AC-01-001] A1: Orders API"; touch -d "@$old" "$TD/1.json"
out=$(watch --sleep 0)
assert "watch: not DONE while the lead has a chore open" test -z "$(grep -x 'DONE' <<<"$out")"
assert "watch: engineers done, the open chores are listed" grep -qxF 'LEAD: [chore] Review' <<<"$out"
assert "watch: ...and a lead with no activity is STALLED" grep -qxF 'STALLED: lead ([chore] Review)' <<<"$out"
assert "watch: ...no engineer is flagged" test -z "$(grep '^STALLED: eng-' <<<"$out")"
assert "watch: --stall-minutes moves the lead's threshold" test -z "$(grep '^STALLED' <<<"$(watch --sleep 0 --stall-minutes 300)")"
touch "$TD/3.json"
assert "watch: a touched lead task file counts as lead activity" test -z "$(grep '^STALLED: lead' <<<"$(watch --sleep 0)")"
touch -d "@$old" "$TD/3.json"
echo more >> "$P/progress.md"; git add "$P/progress.md"; git commit -q -m "docs fresh" -- "$P/progress.md"
out=$(watch --sleep 0)
assert "watch: a fresh commit under docs/product counts as lead activity" test -z "$(grep '^STALLED: lead' <<<"$out")" -a -n "$(grep -x 'LEAD: \[chore\] Review' <<<"$out")"
put 3 lead completed - "[chore] Review"
out=$(watch --sleep 0)
assert "watch: DONE when every task, the lead's included, is completed" grep -qx 'DONE' <<<"$out"
assert "watch: no STALLED or LEAD once everything is completed" test -z "$(grep -E '^(STALLED|LEAD)' <<<"$out")"
rm -f "$TD"/*.json
out=$(watch --sleep 0)
assert "watch: no tasks yet is not an error" grep -q 'no tasks yet' <<<"$out"
assert "watch: ...it prints NO-TASKS and not DONE" test -n "$(grep -x 'NO-TASKS' <<<"$out")" -a -z "$(grep -x 'DONE' <<<"$out")"
mv "$T/home/.claude/tasks" "$TD_HOLD"
out=$(watch --sleep 0); rc=$?
assert "watch: no task folder says so, exit 0" grep -q 'no team task list' <<<"$out"
mv "$TD_HOLD" "$T/home/.claude/tasks"
start=$SECONDS; watch --sleep 1 >/dev/null; (( SECONDS - start >= 1 )) && ok "watch: --sleep waits" || fail "watch: --sleep waits"

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
