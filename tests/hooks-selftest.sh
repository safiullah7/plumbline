#!/usr/bin/env bash
# Self-test for the Plumbline hook scripts. Run from the repo root:
#   bash tests/hooks-selftest.sh
# Works in bash on macOS and Linux, and in Git Bash on Windows.
set -u
if ! command -v jq >/dev/null 2>&1; then
  echo "jq isn't installed or isn't on PATH. Install it (Windows: winget install jqlang.jq),"
  echo "open a new terminal, check 'jq --version', then run this again."
  exit 1
fi
G="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/.claude" "$T/home/.claude/teams/session-test" "$T/tmp"
cd "$T/repo" && git init -q
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
unset CLAUDE_CONFIG_DIR
export PLUMBLINE_TYPECHECK="true" PLUMBLINE_LINT="true"
export PLUMBLINE_TEST_AC='f(){ [ "$1" = "AC-01-001" ]; }; f'

# Agent IDs in the format Claude Code gives teammates: a + name + - + 16 hex.
ENG=aeng-api-e0e49e4975cf862f
STRANGER=astranger-0ec8608094b3bfc5
SUBAGENT=afd684802d721264c

pass=0; failed=0
check() { # name, expected exit, script, json
  local got
  echo "$4" | bash "$G/$3" >/dev/null 2>&1; got=$?
  if [[ $got -eq $2 ]]; then pass=$((pass+1)); echo "ok    $1"
  else failed=$((failed+1)); echo "FAIL  $1 (expected $2, got $got)"; fi
}
json_path() { local p="$1"; printf '%s' "${p//\\/\\\\}"; }
edit() { echo "{\"session_id\":\"s1\",\"agent_id\":\"$1\",\"agent_type\":\"${3:-}\",\"tool_input\":{\"file_path\":\"$(json_path "$2")\"}}"; }
idle='{"session_id":"s1","teammate_name":"eng-api"}'

check "draft: foreign edit allowed"        0 ownership-guard.sh "$(edit $ENG "$T/repo/apps/web/x.ts")"
check "draft: task without AC allowed"     0 task-completed-gate.sh '{"task_subject":"x","teammate_name":"eng-api"}'

# Mark the plan READY and give it Windows (CRLF) line endings, as git may on Windows.
sed 's/^Status: DRAFT/Status: READY/' "$P/dev-plan.md" | awk '{printf "%s\r\n", $0}' > "$T/plan.tmp"
mv "$T/plan.tmp" "$P/dev-plan.md"

check "ready: own file allowed"            0 ownership-guard.sh "$(edit $ENG "$T/repo/apps/api/a.ts")"
check "ready: foreign file blocked"        2 ownership-guard.sh "$(edit $ENG "$T/repo/apps/web/x.ts")"
check "ready: unlisted teammate blocked"   2 ownership-guard.sh "$(edit $STRANGER "$T/repo/apps/api/a.ts")"
check "ready: named by agent_type, blocked" 2 ownership-guard.sh "$(edit other-id "$T/repo/apps/web/x.ts" eng-api)"
check "ready: plain subagent allowed"      0 ownership-guard.sh "$(edit $SUBAGENT "$T/repo/apps/web/x.ts")"
check "ready: questions.md allowed"        0 ownership-guard.sh "$(edit $ENG "$T/repo/$P/questions.md")"
check "ready: lead main thread allowed"    0 ownership-guard.sh "{\"tool_input\":{\"file_path\":\"$T/repo/apps/web/x.ts\"}}"
if command -v cygpath >/dev/null 2>&1; then
  check "ready: Windows path, own file"     0 ownership-guard.sh "$(edit $ENG "$(cygpath -w "$T/repo/apps/api/a.ts")")"
  check "ready: Windows path, foreign file" 2 ownership-guard.sh "$(edit $ENG "$(cygpath -w "$T/repo/apps/web/x.ts")")"
fi
check "ready: task without AC blocked"     2 task-completed-gate.sh '{"task_subject":"x","teammate_name":"eng-api"}'
check "ready: task with passing AC"        0 task-completed-gate.sh '{"task_subject":"[AC-01-001] x","teammate_name":"eng-api"}'
check "ready: task with failing AC"        2 task-completed-gate.sh '{"task_subject":"[AC-01-002] x","teammate_name":"eng-api"}'
check "ready: task outside a team"         0 task-completed-gate.sh '{"task_subject":"x"}'
check "ready: idle with clean tree"        0 teammate-idle-gate.sh "$idle"
mkdir -p apps/api && echo x > apps/api/a.ts
check "ready: idle, dirty file, 1st push"  2 teammate-idle-gate.sh "$idle"
check "ready: idle, dirty file, 2nd push"  2 teammate-idle-gate.sh "$idle"
check "ready: idle, dirty file, gives up"  0 teammate-idle-gate.sh "$idle"

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
