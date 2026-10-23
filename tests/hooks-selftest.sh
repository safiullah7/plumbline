#!/usr/bin/env bash
# Self-test for the Plumbline hook scripts. Run from the repo root:
#   bash tests/hooks-selftest.sh
# Works in bash on macOS and Linux, and in Git Bash on Windows. On Windows, also
# run it with TMPDIR=/c/Users/$USERNAME/AppData/Local/Temp: Git Bash names that
# folder two ways, and the path checks must treat both as the same place.
set -u
if ! command -v jq >/dev/null 2>&1; then
  echo "jq isn't installed or isn't on PATH. Install it (Windows: winget install jqlang.jq),"
  echo "open a new terminal, check 'jq --version', then run this again."
  exit 1
fi
G="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/.claude" "$T/home/.claude/teams/session-test" "$T/tmp" "$T/data"
cd "$T/repo" && git init -q && git config core.autocrlf false
P=docs/product/demo/phases/phase-01; mkdir -p "$P"; echo "$P" > .claude/current-phase
cat > "$P/dev-plan.md" <<'PLAN'
# Phase 01 dev plan

Status: DRAFT

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-api | apps/api/** |
| design | docs/product/** |
PLAN
# Like real sessions: the team config lists only the lead.
echo '{"members":[{"agentId":"team-lead@session-test","name":"team-lead"}]}' \
  > "$T/home/.claude/teams/session-test/config.json"
export HOME="$T/home" CLAUDE_PROJECT_DIR="$T/repo" TMPDIR="$T/tmp"
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_DATA
export PLUMBLINE_TYPECHECK="true" PLUMBLINE_LINT="true"
export PLUMBLINE_TEST_AC='f(){ [ "$1" = "AC-01-001" ]; }; f'

# Agent IDs in the format Claude Code gives teammates: a + name + - + 16 hex.
ENG=aeng-api-e0e49e4975cf862f
STRANGER=astranger-0ec8608094b3bfc5
SUBAGENT=afd684802d721264c

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
check() { # name, expected exit, script, json
  local got
  echo "$4" | bash "$G/$3" >/dev/null 2>&1; got=$?
  if [[ $got -eq $2 ]]; then ok "$1"; else fail "$1 (expected $2, got $got)"; fi
}
check_out() { # name, expected exit, script, json, text the output must contain
  local got out
  out=$(echo "$4" | bash "$G/$3" 2>&1); got=$?
  if [[ $got -ne $2 ]]; then fail "$1 (expected $2, got $got)"
  elif [[ "$out" != *"$5"* ]]; then fail "$1 (output lacks: $5)"
  else ok "$1"; fi
}
assert() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
json_path() { local p="$1"; printf '%s' "${p//\\/\\\\}"; }
edit() { echo "{\"session_id\":\"s1\",\"agent_id\":\"$1\",\"agent_type\":\"${3:-}\",\"tool_input\":{\"file_path\":\"$(json_path "$2")\"}}"; }
idle() { echo "{\"session_id\":\"s1\",\"teammate_name\":\"$1\"}"; }

check "draft: foreign edit allowed"        0 ownership-guard.sh "$(edit $ENG "$T/repo/apps/web/x.ts")"
check "draft: task without AC allowed"     0 task-completed-gate.sh '{"task_subject":"x","teammate_name":"eng-api"}'
check "draft: untagged task creation allowed" 0 task-created-gate.sh '{"task_subject":"x"}'

# Mark the plan READY and give it Windows (CRLF) line endings, as git may on Windows.
# Commit the fixture so only the files each case creates count as uncommitted work.
sed 's/^Status: DRAFT/Status: READY/' "$P/dev-plan.md" | awk '{printf "%s\r\n", $0}' > "$T/plan.tmp"
mv "$T/plan.tmp" "$P/dev-plan.md"
git add -A && git -c user.name=selftest -c user.email=selftest@example.com commit -qm fixture

check "ready: own file allowed"            0 ownership-guard.sh "$(edit $ENG "$T/repo/apps/api/a.ts")"
check "ready: foreign file blocked"        2 ownership-guard.sh "$(edit $ENG "$T/repo/apps/web/x.ts")"
check "ready: unlisted teammate blocked"   2 ownership-guard.sh "$(edit $STRANGER "$T/repo/apps/api/a.ts")"
check "ready: named by agent_type, blocked" 2 ownership-guard.sh "$(edit other-id "$T/repo/apps/web/x.ts" eng-api)"
check "ready: plain subagent allowed"      0 ownership-guard.sh "$(edit $SUBAGENT "$T/repo/apps/web/x.ts")"
check "ready: questions.md allowed"        0 ownership-guard.sh "$(edit $ENG "$T/repo/$P/questions.md")"
check "ready: lead main thread allowed"    0 ownership-guard.sh "{\"tool_input\":{\"file_path\":\"$T/repo/apps/web/x.ts\"}}"
if command -v cygpath >/dev/null 2>&1; then
  check "ready: Windows path, own file"       0 ownership-guard.sh "$(edit $ENG "$(cygpath -w "$T/repo/apps/api/a.ts")")"
  check "ready: Windows path, foreign file"   2 ownership-guard.sh "$(edit $ENG "$(cygpath -w "$T/repo/apps/web/x.ts")")"
  check "ready: Windows path, unlisted blocked" 2 ownership-guard.sh "$(edit $STRANGER "$(cygpath -w "$T/repo/apps/api/a.ts")")"
  # The same folder under its other Git Bash spelling (/c/... instead of /tmp/...).
  w=$(cygpath -m "$T/repo"); d="${w:0:1}"; alias_dir="/${d,,}${w:2}"
  CLAUDE_PROJECT_DIR="$alias_dir"
  check "ready: other spelling, own file"     0 ownership-guard.sh "$(edit $ENG "$(cygpath -w "$T/repo/apps/api/a.ts")")"
  check "ready: other spelling, foreign file" 2 ownership-guard.sh "$(edit $ENG "$(cygpath -w "$T/repo/apps/web/x.ts")")"
  CLAUDE_PROJECT_DIR="$T/repo"
fi
check "ready: task without AC blocked"     2 task-completed-gate.sh '{"task_subject":"x","teammate_name":"eng-api"}'
check "ready: task with passing AC"        0 task-completed-gate.sh '{"task_subject":"[AC-01-001] x","teammate_name":"eng-api"}'
check "ready: task with failing AC"        2 task-completed-gate.sh '{"task_subject":"[AC-01-002] x","teammate_name":"eng-api"}'
check "ready: task outside a team"         0 task-completed-gate.sh '{"task_subject":"x"}'
check "ready: [chore] task completes without AC tests" 0 task-completed-gate.sh '{"task_subject":"[chore] Land contracts","teammate_name":"eng-api"}'
assert "ready: gate timing hidden by default" \
  test -z "$(echo '{"task_subject":"[AC-01-001] x","teammate_name":"eng-api"}' | bash "$G/task-completed-gate.sh" 2>&1)"
export PLUMBLINE_HOOK_TIMING=1
check_out "ready: gate timing shown when asked" 0 task-completed-gate.sh '{"task_subject":"[AC-01-001] x","teammate_name":"eng-api"}' "Task gate passed: typecheck"
unset PLUMBLINE_HOOK_TIMING

# Task creation gate: lead-created tasks have no teammate_name, so all are gated.
check_out "ready: untagged task creation refused" 2 task-created-gate.sh '{"task_subject":"Polish the UI"}' "names no AC IDs"
check "ready: tagged task creation allowed"   0 task-created-gate.sh '{"task_subject":"[AC-01-002] Duplicate names","teammate_name":"eng-api"}'
check "ready: [chore] task creation allowed"  0 task-created-gate.sh '{"task_subject":"[chore] Land contracts"}'

# Context injection: the lead (SessionStart) and teammates (SubagentStart).
ctx() { echo "$1" | bash "$G/context.sh" 2>/dev/null; }
out=$(ctx '{"hook_event_name":"SessionStart","session_id":"s1","source":"startup"}')
assert "context: lead gets valid JSON" jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<<"$out"
assert "context: lead sees phase and status" grep -q "$P (dev plan: READY)" <<<"$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"
out=$(ctx "{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$ENG\",\"agent_type\":\"plumbline:senior-engineer\"}")
assert "context: teammate sees its ownership" grep -q "You are eng-api. You own: apps/api/\*\*" <<<"$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"
assert "context: plain subagent gets nothing" test -z "$(ctx "{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$SUBAGENT\",\"agent_type\":\"Explore\"}")"
assert "context: plumbline agent without a row gets the phase" grep -q "Plumbline phase" <<<"$(ctx "{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$SUBAGENT\",\"agent_type\":\"plumbline:code-reviewer\"}")"
assert "context: silent without an active phase" test -z "$(cd "$T/home" && CLAUDE_PROJECT_DIR="$T/home" ctx '{"hook_event_name":"SessionStart"}')"

# Idle gate. Hook state lives in CLAUDE_PLUGIN_DATA, which Claude Code passes as a Windows path.
data="$T/data"; command -v cygpath >/dev/null 2>&1 && data=$(cygpath -m "$T/data")
export CLAUDE_PLUGIN_DATA="$data"
Q="$P/questions.md"
check "ready: idle with clean tree"        0 teammate-idle-gate.sh "$(idle eng-api)"
mkdir -p apps/api && echo x > apps/api/a.ts
check "ready: idle, dirty file, 1st push"  2 teammate-idle-gate.sh "$(idle eng-api)"
assert "ready: idle state kept in CLAUDE_PLUGIN_DATA" test -f "$T/data/plumbline-idle/s1-eng-api"
check_out "ready: idle, 2nd push names the lead" 2 teammate-idle-gate.sh "$(idle eng-api)" "SendMessage the lead"
check "ready: idle, dirty file, gives up"  0 teammate-idle-gate.sh "$(idle eng-api)"
assert "ready: give-up creates questions.md with its header" grep -q '^| # | From | To | Question | Answer | Status |' "$Q"
assert "ready: give-up logs one ESCALATED row naming the file" \
  test "$(grep -c 'ESCALATED |' "$Q" 2>/dev/null)" = 1 -a "$(grep -c 'apps/api/a.ts' "$Q" 2>/dev/null)" = 1
check "ready: idle again after giving up"  0 teammate-idle-gate.sh "$(idle eng-api)"
assert "ready: no duplicate ESCALATED row" test "$(grep -c 'ESCALATED |' "$Q" 2>/dev/null)" = 1
echo >> "$Q"   # make sure questions.md is uncommitted work inside design's folder
mkdir -p "$P/briefs" && echo x > "$P/briefs/eng-api.md" && echo x > "$P/progress.md"
check "ready: dirty shared files don't bounce their owner" 0 teammate-idle-gate.sh "$(idle design)"
out=$(ctx '{"hook_event_name":"SessionStart"}' | jq -r .hookSpecificOutput.additionalContext)
assert "context: lead sees the escalation" grep -q "1 escalated" <<<"$out"
assert "context: stays within 60 lines and 10,000 chars" test "$(wc -l <<<"$out")" -le 60 -a "${#out}" -lt 10000
rm -f apps/api/a.ts
mkdir -p "apps/api/with space" && echo x > "apps/api/with space/b.ts"
check "ready: dirty file with a space in its path counts" 2 teammate-idle-gate.sh "$(idle eng-api)"

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
