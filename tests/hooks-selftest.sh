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

# Hook input for a tool call: $1 = agent_id (empty for the main session), $2 = tool_input as JSON.
mk() { jq -nc --arg id "$1" --argjson ti "$2" 'if $id == "" then {tool_input: $ti} else {agent_id: $id, agent_type: "", tool_input: $ti} end'; }
N="$T/repo/apps/api/notes.md"   # a file eng-api owns, so only the content can get a case blocked
ti_write() { jq -nc --arg f "$N" --arg c "$1" '{file_path: $f, content: $c}'; }
ti_edit()  { jq -nc --arg f "$N" --arg c "$1" '{file_path: $f, old_string: "x", new_string: $c}'; }
ti_multi() { jq -nc --arg f "$N" --arg c "$1" '{file_path: $f, edits: [{old_string: "a", new_string: "b"}, {old_string: "x", new_string: $c}]}'; }
WAIVER=$'Result: fail\nAccessibility waived: no screen reader on this surface (approved by Sam)\n'
F="$T/fixtures"; mkdir -p "$F"   # files the waiver cases edit, outside the repo
ti_write_at() { jq -nc --arg f "$1" --arg c "$2" '{file_path: $f, content: $c}'; }
ti_edit_at()  { jq -nc --arg f "$1" --arg o "$2" --arg n "$3" '{file_path: $f, old_string: $o, new_string: $n}'; }
ti_path()     { jq -nc --arg f "$1" '{file_path: $f, content: "profile=full"}'; }
# Hook input for a Bash call: $1 = agent_id (empty for the main session), $2 = the command.
mkb() { jq -nc --arg id "$1" --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}} + (if $id == "" then {} else {agent_id: $id, agent_type: ""} end)'; }

# The locks that apply to any agent, the plan READY or not: $1 labels the cases.
lock_cases() {
  local k a ti c
  for a in "$ENG" "$SUBAGENT"; do
    k=teammate; [[ "$a" == "$SUBAGENT" ]] && k=subagent
    check "$1: waiver line blocked, $k Write"     2 ownership-guard.sh "$(mk "$a" "$(ti_write "$WAIVER")")"
    check "$1: waiver line blocked, $k Edit"      2 ownership-guard.sh "$(mk "$a" "$(ti_edit "$WAIVER")")"
    check "$1: waiver line blocked, $k MultiEdit" 2 ownership-guard.sh "$(mk "$a" "$(ti_multi "$WAIVER")")"
  done
  check_out "$1: waiver refusal says who can approve" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write "$WAIVER")")" "Only the user can approve a waiver"
  check "$1: waiver line allowed in the main session" 0 ownership-guard.sh "$(mk "" "$(ti_write "$WAIVER")")"
  check "$1: Evidence waived blocked"     2 ownership-guard.sh "$(mk "$ENG" "$(ti_write $'Evidence waived: transcript (api) - no network (approved by Sam)')")"
  check "$1: list-marker variant blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write $'- Evidence waived: contract (api) - n/a (approved by Sam)')")"
  check "$1: indented variant blocked"    2 ownership-guard.sh "$(mk "$SUBAGENT" "$(ti_write $'  - Accessibility waived: none (approved by Sam)')")"
  check "$1: lowercase variant blocked"   2 ownership-guard.sh "$(mk "$ENG" "$(ti_write $'accessibility waived: none (approved by Sam)')")"
  ti='If axe cannot run, record that here as "Accessibility waived: <reason> (approved by <who>)".'
  check "$1: mid-sentence mention allowed" 0 ownership-guard.sh "$(mk "$ENG" "$(ti_write "$ti")")"
  check "$1: placeholder-only line blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write $'Accessibility waived: <reason> (approved by <who>)')")"
  check "$1: Evidence placeholder line blocked" 2 ownership-guard.sh "$(mk "$SUBAGENT" "$(ti_write $'- Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)')")"
  check "$1: real waiver with a trailing placeholder blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write $'Accessibility waived: none (approved by Sam) <name>')")"
  check "$1: bold variant blocked"        2 ownership-guard.sh "$(mk "$ENG" "$(ti_write $'> **Accessibility waived:** none (approved by Sam)')")"
  check "$1: heading, dashed variant blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write $'### Evidence-waived : none (approved by Sam)')")"
  # The guard judges the file the edit would produce, against the file as it is now.
  printf 'Result: fail\nAccessibility notes: x\n' > "$F/notes.md"
  printf '# QA\nResult: fail\nAccessibility waived: none (approved by Sam)\n' > "$F/qa-report.md"
  for a in "$ENG" "$SUBAGENT"; do
    k=teammate; [[ "$a" == "$SUBAGENT" ]] && k=subagent
    check "$1: waiver pieced together by Edit blocked, $k" 2 ownership-guard.sh "$(mk "$a" "$(ti_edit_at "$F/notes.md" "notes: x" "waived: no browser (approved by Safi)")")"
  done
  check "$1: waiver pieced together by MultiEdit blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(jq -nc --arg f "$F/notes.md" '{file_path: $f, edits: [{old_string: "fail", new_string: "pass"}, {old_string: "notes", new_string: "waived"}]}')")"
  check "$1: waiver pieced together by Edit, main session allowed" 0 ownership-guard.sh "$(mk "" "$(ti_edit_at "$F/notes.md" "notes: x" "waived: no browser (approved by Safi)")")"
  if command -v cygpath >/dev/null 2>&1; then
    check "$1: waiver pieced together, Windows path, blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_edit_at "$(cygpath -w "$F/notes.md")" "notes: x" "waived: no browser (approved by Safi)")")"
  fi
  check "$1: Edit beside an approved waiver allowed" 0 ownership-guard.sh "$(mk "$ENG" "$(ti_edit_at "$F/qa-report.md" "Result: fail" "Result: pass")")"
  check "$1: Edit that carries the approved waiver along allowed" 0 ownership-guard.sh "$(mk "$SUBAGENT" "$(ti_edit_at "$F/qa-report.md" $'Result: fail\nAccessibility waived: none (approved by Sam)' $'Result: pass\nAccessibility waived: none (approved by Sam)')")"
  check "$1: Edit that changes the approved waiver blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_edit_at "$F/qa-report.md" "none (approved by Sam)" "everything (approved by Sam)")")"
  check "$1: Write that keeps the approved waiver allowed" 0 ownership-guard.sh "$(mk "$ENG" "$(ti_write_at "$F/qa-report.md" $'# QA\nResult: pass\n\n  Accessibility waived: none (approved by Sam)\n')")"
  check "$1: Write that adds a second waiver blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write_at "$F/qa-report.md" $'# QA\nResult: pass\nAccessibility waived: none (approved by Sam)\nEvidence waived: transcript (api) - n/a (approved by Sam)\n')")"
  check "$1: Write that adds a second waiver, main session allowed" 0 ownership-guard.sh "$(mk "" "$(ti_write_at "$F/qa-report.md" $'# QA\nResult: pass\nAccessibility waived: none (approved by Sam)\nEvidence waived: transcript (api) - n/a (approved by Sam)\n')")"
  check "$1: Write of the waiver to another file blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write_at "$F/copy.md" $'Accessibility waived: none (approved by Sam)\n')")"
  check "$1: NotebookEdit waiver blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(jq -nc --arg f "$F/n.ipynb" '{notebook_path: $f, new_source: "Accessibility waived: none (approved by Sam)"}')")"
  check "$1: .plumbline write blocked, teammate" 2 ownership-guard.sh "$(mk "$ENG" '{"file_path":"'"$T"'/repo/docs/product/demo/07-x/.plumbline","content":"profile=full"}')"
  check "$1: .plumbline edit blocked, subagent" 2 ownership-guard.sh "$(mk "$SUBAGENT" '{"file_path":"'"$T"'/repo/docs/product/demo/07-x/.plumbline","old_string":"a","new_string":"b"}')"
  check_out "$1: .plumbline refusal names kickoff.sh" 2 ownership-guard.sh "$(mk "$ENG" '{"file_path":"C:\\repo\\x\\.plumbline","content":"a"}')" "written by kickoff.sh"
  check "$1: .plumbline write allowed in the main session" 0 ownership-guard.sh "$(mk "" '{"file_path":"'"$T"'/repo/docs/product/demo/07-x/.plumbline","content":"profile=full"}')"
  check "$1: a file merely named like .plumbline-x allowed" 0 ownership-guard.sh "$(mk "$ENG" '{"file_path":"'"$T"'/repo/apps/api/.plumbline-notes","content":"a"}')"
  # docs/product/project.md lists the commands the gates run: no agent changes it.
  local pm="$T/repo/docs/product/project.md"
  for a in "$ENG" "$SUBAGENT"; do
    k=teammate; [[ "$a" == "$SUBAGENT" ]] && k=subagent
    check "$1: project.md Write blocked, $k"      2 ownership-guard.sh "$(mk "$a" "$(ti_write_at "$pm" 'x')")"
    check "$1: project.md Edit blocked, $k"       2 ownership-guard.sh "$(mk "$a" "$(ti_edit_at "$pm" a b)")"
    check "$1: project.md MultiEdit blocked, $k"  2 ownership-guard.sh "$(mk "$a" "$(jq -nc --arg f "$pm" '{file_path: $f, edits: [{old_string: "a", new_string: "b"}]}')")"
    check "$1: project.md relative path blocked, $k" 2 ownership-guard.sh "$(mk "$a" "$(ti_write_at 'docs/product/project.md' 'x')")"
    check "$1: project.md spelled with a trailing dot blocked, $k" 2 ownership-guard.sh "$(mk "$a" "$(ti_write_at "$pm." 'x')")"
    check "$1: project.md Bash redirect blocked, $k"  2 ownership-guard.sh "$(mkb "$a" "echo x > docs/product/project.md")"
    check "$1: project.md Bash sed -i blocked, $k"    2 ownership-guard.sh "$(mkb "$a" "sed -i s/x/y/ docs/product/project.md")"
  done
  if command -v cygpath >/dev/null 2>&1; then
    pw=$(cygpath -w "$pm"); pw="${pw/project.md/Project.MD}"; pw="${pw/\\docs\\/\\DOCS\\}"
    for a in "$ENG" "$SUBAGENT"; do
      check "$1: project.md Windows path, odd case, blocked" 2 ownership-guard.sh "$(mk "$a" "$(ti_write_at "$pw" 'x')")"
    done
  fi
  check "$1: project.md upper-case spelling blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write_at "$T/repo/DOCS/Product/Project.MD" 'x')")"
  check_out "$1: project.md refusal says only the user changes it" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_write_at "$pm" 'x')")" "only the user changes it"
  check "$1: project.md Write allowed in the main session" 0 ownership-guard.sh "$(mk "" "$(ti_write_at "$pm" 'x')")"
  check "$1: project.md Bash read allowed" 0 ownership-guard.sh "$(mkb "$ENG" "cat docs/product/project.md")"
  check "$1: project.md Bash read with grep and pipe allowed" 0 ownership-guard.sh "$(mkb "$SUBAGENT" "grep -n api docs/product/project.md | head")"
  check "$1: project.md Bash write allowed in the main session" 0 ownership-guard.sh "$(mkb "" "echo x > docs/product/project.md")"
  check "$1: another project.md-like file allowed" 0 ownership-guard.sh "$(mk "$ENG" "$(ti_write_at "$T/repo/apps/api/project.md.bak" 'x')")"
  # Other spellings of the same file on NTFS and APFS.
  local f
  for f in .Plumbline ".plumbline " .plumbline. '.plumbline::$DATA' ".PLUMBLINE. ."; do
    check "$1: .plumbline spelled '$f' blocked" 2 ownership-guard.sh "$(mk "$ENG" "$(ti_path "$T/repo/docs/product/demo/01-a/$f")")"
  done
  check "$1: backslash path, spelled .Plumbline. blocked" 2 ownership-guard.sh "$(mk "$SUBAGENT" "$(ti_path 'C:\repo\docs\product\demo\01-a\.Plumbline.')")"
  check "$1: .Plumbline allowed in the main session" 0 ownership-guard.sh "$(mk "" "$(ti_path "$T/repo/docs/product/demo/01-a/.Plumbline")")"

  # Bash: a best-effort check of the command, never the ownership table.
  for a in "$ENG" "$SUBAGENT"; do
    k=teammate; [[ "$a" == "$SUBAGENT" ]] && k=subagent
    check "$1: Bash waiver append blocked, $k" 2 ownership-guard.sh "$(mkb "$a" "echo 'Accessibility waived: x (approved by Sam)' >> qa-report.md")"
    check "$1: Bash .plumbline redirect blocked, $k" 2 ownership-guard.sh "$(mkb "$a" "echo x > a/.plumbline")"
  done
  check_out "$1: Bash waiver refusal says how to search" 2 ownership-guard.sh "$(mkb "$ENG" "printf '%s\n' 'evidence waived : x' | tee -a qa-report.md")" 'grep for "waived" without the colon'
  check "$1: Bash grep for waived allowed" 0 ownership-guard.sh "$(mkb "$ENG" "grep -n waived qa-report.md")"
  check "$1: Bash grep for the phrase without colon allowed" 0 ownership-guard.sh "$(mkb "$ENG" "grep -n 'Accessibility waived' qa-report.md")"
  for c in "sed -i s/x/y/ a/.plumbline" "sed -i.bak -e s/x/y/ a/.plumbline" "perl -pi -e s/x/y/ a/.plumbline" \
      "printf x >a/.Plumbline" "echo x 2>&1 >> a/.plumbline" "tee -a a/.plumbline < x" "mv /tmp/x a/.plumbline" \
      "cp x a/.plumbline" "rm -f a/.plumbline" "truncate -s 0 a/.plumbline" "dd if=x of=a/.plumbline" \
      "cd docs && echo x > a/.plumbline"; do
    check "$1: Bash write to .plumbline blocked: $c" 2 ownership-guard.sh "$(mkb "$SUBAGENT" "$c")"
  done
  check "$1: Bash write to .plumbline over a continued line blocked" 2 ownership-guard.sh "$(mkb "$SUBAGENT" $'echo x \\\n  > a/.plumbline')"
  for c in "cat a/.plumbline" "cat a/.plumbline 2>/dev/null" "grep profile= a/.plumbline" "sed -n p docs/07-impl/.plumbline" \
      "cat a/.plumbline | tee /tmp/copy" "cat a/.plumbline > /tmp/copy" "ls -la a/ && cat a/.plumbline-notes"; do
    check "$1: Bash read of .plumbline allowed: $c" 0 ownership-guard.sh "$(mkb "$ENG" "$c")"
  done
  check "$1: Bash write outside owned files allowed" 0 ownership-guard.sh "$(mkb "$ENG" "echo x > $T/repo/apps/web/x.ts")"
  for c in "echo 'Accessibility waived: x (approved by Sam)' >> qa-report.md" "echo x > a/.plumbline" "sed -i s/x/y/ a/.plumbline"; do
    check "$1: Bash in the main session never blocked: $c" 0 ownership-guard.sh "$(mkb "" "$c")"
  done
}

check "draft: foreign edit allowed"        0 ownership-guard.sh "$(edit $ENG "$T/repo/apps/web/x.ts")"
check "draft: task without AC allowed"     0 task-completed-gate.sh '{"task_subject":"x","teammate_name":"eng-api"}'
check "draft: untagged task creation allowed" 0 task-created-gate.sh '{"task_subject":"x"}'
lock_cases draft

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
lock_cases ready
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
assert "context: lead is told where the scripts are" grep -qE "^Plumbline scripts: .*plugins/plumbline/scripts$" <<<"$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"
out=$(ctx "{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$ENG\",\"agent_type\":\"plumbline:senior-engineer\"}")
assert "context: teammate sees its ownership" grep -q "You are eng-api. You own: apps/api/\*\*" <<<"$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"
assert "context: plain subagent gets nothing" test -z "$(ctx "{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$SUBAGENT\",\"agent_type\":\"Explore\"}")"
assert "context: plumbline agent without a row gets the phase" grep -q "Plumbline phase" <<<"$(ctx "{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$SUBAGENT\",\"agent_type\":\"plumbline:code-reviewer\"}")"
assert "context: silent without an active phase" test -z "$(cd "$T/home" && CLAUDE_PROJECT_DIR="$T/home" ctx '{"hook_event_name":"SessionStart"}')"
ctx_text() { jq -r '.hookSpecificOutput.additionalContext // empty' | tr -d '\r'; }
SESSION='{"hook_event_name":"SessionStart","session_id":"s1","source":"startup"}'
TEAMMATE_START="{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$ENG\",\"agent_type\":\"plumbline:senior-engineer\"}"
REVIEWER_START="{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$SUBAGENT\",\"agent_type\":\"plumbline:code-reviewer\"}"
EXPLORE_START="{\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$SUBAGENT\",\"agent_type\":\"Explore\"}"
assert "context: legacy phase gets its folder name as Module" grep -qx "Module: demo" <<<"$(ctx "$SESSION" | ctx_text)"
printf 'profile=lean\nmodule=room-schedules\n' > "$P/.plumbline"
assert "context: lead sees Module from .plumbline" grep -qx "Module: room-schedules" <<<"$(ctx "$SESSION" | ctx_text)"
assert "context: Module follows the phase line" test "$(ctx "$SESSION" | ctx_text | sed -n 2p)" = "Module: room-schedules"
assert "context: teammate sees Module" grep -qx "Module: room-schedules" <<<"$(ctx "$TEAMMATE_START" | ctx_text)"
rm -f "$P/.plumbline"
# Surfaces: a Surfaces line from .plumbline, plus each surface's profile commands.
assert "context: no Surfaces line without surfaces=" test -z "$(ctx "$SESSION" | ctx_text | grep -E '^Surfaces?')"
printf 'module=rooms\nsurfaces=api,cli,web-ui-shop\n' > "$P/.plumbline"
assert "context: Surfaces line without a profile" grep -qx "Surfaces: api,cli,web-ui-shop" <<<"$(ctx "$SESSION" | ctx_text)"
assert "context: no per-surface lines without a profile" test -z "$(ctx "$SESSION" | ctx_text | grep '^Surface ')"
assert "context: Surfaces comes right after Module" test "$(ctx "$SESSION" | ctx_text | sed -n 3p)" = "Surfaces: api,cli,web-ui-shop"
mkdir -p docs/product
cat > docs/product/project.md <<'PROFILE'
# Project profile

## Surfaces
| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |
| --- | --- | --- | --- | --- | --- | --- |
| api | node | apps/api/** | npm start | npx tsc -p apps/api | npx eslint apps/api | node --dir apps/api |
| cli | go | cmd/** | | | golangci-lint run | go |
| web-ui | react | apps/web/** | npm run dev | | | generic |
| mobile-ui | rn | apps/mobile/** | | | | |
PROFILE
out=$(ctx "$SESSION" | ctx_text)
assert "context: Surface api line is the ac-check.sh command" grep -qxF "Surface api: check with bash \"$G/ac-check.sh\" \"<IDs>\" --surface api" <<<"$out"
assert "context: Surface line doesn't show the raw cells" test -z "$(grep -E '^Surface .*(npx|node --dir|golangci)' <<<"$out")"
assert "context: Surface line names the same scripts folder as the Plumbline scripts line" grep -qxF "Plumbline scripts: $G" <<<"$out"
assert "context: a row with some cells gets its line" grep -qxF "Surface cli: check with bash \"$G/ac-check.sh\" \"<IDs>\" --surface cli" <<<"$out"
assert "context: a profile row for a surface the feature doesn't list gets no line" test -z "$(grep -E '^Surface (web-ui|mobile-ui):' <<<"$out")"
assert "context: a feature surface the profile lacks gets no line" test -z "$(grep '^Surface web-ui-shop' <<<"$out")"
assert "context: profile lines stay in the Module/Surfaces block" test "$(grep -n '^Surface ' <<<"$out" | head -n1 | cut -d: -f1)" = 4
assert "context: teammate sees the Surfaces line too" grep -qx "Surfaces: api,cli,web-ui-shop" <<<"$(ctx "$TEAMMATE_START" | ctx_text)"
printf 'module=rooms\nsurfaces=mobile-ui\n' > "$P/.plumbline"
out=$(ctx "$SESSION" | ctx_text)
assert "context: Surfaces line when the row has no commands" grep -qx "Surfaces: mobile-ui" <<<"$out"
assert "context: a row with only empty cells adds no line" test -z "$(grep '^Surface mobile-ui' <<<"$out")"
printf 'module=rooms\nsurfaces=api\n' > "$P/.plumbline"
sb=$(git symbolic-ref --short HEAD); git checkout -q -b quick/surf-check
printf 'branch=quick/surf-check\nids=AC-01-001\n' > .claude/plumbline-quick
out=$(ctx "$SESSION" | ctx_text)
assert "context: Quick marker still swaps the context with surfaces=" grep -qxF "Plumbline Quick change in progress (branch quick/surf-check): no feature folder; don't write phase docs." <<<"$out"
assert "context: Quick marker hides Surfaces lines" test -z "$(grep -E '^Surfaces?[: ]' <<<"$out")"
rm -f .claude/plumbline-quick
git checkout -q "$sb" && git branch -q -D quick/surf-check
rm -f "$P/.plumbline" docs/product/project.md
assert "context: no Surfaces line once surfaces= is gone" test -z "$(ctx "$SESSION" | ctx_text | grep -E '^Surfaces?')"
# A Quick change swaps the feature context for a one-line notice and keeps the scripts line.
# The build skill creates the quick branch before it writes the marker.
main_branch=$(git symbolic-ref --short HEAD)
git checkout -q -b quick/fix-typo
printf 'branch=quick/fix-typo\nids=AC-01-001\n' > .claude/plumbline-quick
for case_in in "lead|$SESSION" "teammate|$TEAMMATE_START" "plumbline agent|$REVIEWER_START"; do
  out=$(ctx "${case_in#*|}" | ctx_text); k="${case_in%%|*}"
  assert "context: Quick marker names the branch ($k)" grep -qxF "Plumbline Quick change in progress (branch quick/fix-typo): no feature folder; don't write phase docs." <<<"$out"
  assert "context: Quick marker keeps the scripts line ($k)" grep -qE "^Plumbline scripts: .*plugins/plumbline/scripts$" <<<"$out"
  assert "context: Quick marker hides the feature ($k)" test -z "$(grep -E 'Plumbline phase|Module:|docs/product|You own' <<<"$out")"
done
assert "context: Quick marker, plain subagent still gets nothing" test -z "$(ctx "$EXPLORE_START")"
assert "context: Quick marker, valid JSON for SubagentStart" jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"' <<<"$(ctx "$TEAMMATE_START")"
# A marker left behind on another branch is stale; without a branch (detached HEAD) it still counts.
git checkout -q "$main_branch"
out=$(ctx "$SESSION" | ctx_text)
assert "context: stale Quick marker on another branch ignored" grep -q "Plumbline phase: $P" <<<"$out"
assert "context: stale Quick marker on another branch, no notice" test -z "$(grep 'Quick change' <<<"$out")"
assert "context: stale Quick marker, teammate gets its ownership" grep -q "You are eng-api" <<<"$(ctx "$TEAMMATE_START" | ctx_text)"
git checkout -q --detach
assert "context: Quick marker counts on a detached HEAD" grep -q "Plumbline Quick change in progress (branch quick/fix-typo)" <<<"$(ctx "$SESSION" | ctx_text)"
git checkout -q "$main_branch" && git branch -q -D quick/fix-typo
rm -f .claude/plumbline-quick
assert "context: feature context returns once the marker is gone" grep -q "Plumbline phase: $P" <<<"$(ctx "$SESSION" | ctx_text)"

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
assert "ready: legacy phase folder keeps '# Phase 01 questions'" test "$(head -n1 "$Q" | tr -d '\r')" = "# Phase 01 questions"
assert "ready: give-up logs one ESCALATED row naming the file" \
  test "$(grep -c 'ESCALATED |' "$Q" 2>/dev/null)" = 1 -a "$(grep -c 'apps/api/a.ts' "$Q" 2>/dev/null)" = 1
check "ready: idle again after giving up"  0 teammate-idle-gate.sh "$(idle eng-api)"
assert "ready: no duplicate ESCALATED row" test "$(grep -c 'ESCALATED |' "$Q" 2>/dev/null)" = 1
echo >> "$Q"   # make sure questions.md is uncommitted work inside design's folder
mkdir -p "$P/briefs" "$P/qa/shots" "$P/qa/a11y" && echo x > "$P/briefs/eng-api.md" && echo x > "$P/progress.md"
echo x > "$P/qa/shots/rooms-390.png" && echo '{}' > "$P/qa/a11y/rooms-390.json"
check "ready: dirty shared files don't bounce their owner" 0 teammate-idle-gate.sh "$(idle design)"
out=$(ctx '{"hook_event_name":"SessionStart"}' | jq -r .hookSpecificOutput.additionalContext)
assert "context: lead sees the escalation" grep -q "1 escalated" <<<"$out"
assert "context: stays within 60 lines and 10,000 chars" test "$(wc -l <<<"$out")" -le 60 -a "${#out}" -lt 10000
rm -f apps/api/a.ts
mkdir -p "apps/api/with space" && echo x > "apps/api/with space/b.ts"
check "ready: dirty file with a space in its path counts" 2 teammate-idle-gate.sh "$(idle eng-api)"

# A new-layout feature folder: the questions.md header comes from the folder name.
P2=docs/product/demo/07-x; mkdir -p "$P2"; echo "$P2" > .claude/current-phase
sed 's/^Status: DRAFT/Status: READY/' > "$P2/dev-plan.md" <<'PLAN'
# 07-x dev plan

Status: DRAFT

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-api | apps/api/** |
PLAN
idle2() { echo "{\"session_id\":\"s2\",\"teammate_name\":\"$1\"}"; }
check "new layout: idle, 1st push"   2 teammate-idle-gate.sh "$(idle2 eng-api)"
check "new layout: idle, 2nd push"   2 teammate-idle-gate.sh "$(idle2 eng-api)"
check "new layout: idle, gives up"   0 teammate-idle-gate.sh "$(idle2 eng-api)"
assert "new layout: questions.md header is the folder name" test "$(head -n1 "$P2/questions.md" | tr -d '\r')" = "# 07-x questions"
assert "new layout: questions.md has the table and one ESCALATED row" \
  test "$(grep -c '^| # | From | To | Question | Answer | Status |' "$P2/questions.md")" = 1 -a "$(grep -c 'ESCALATED |' "$P2/questions.md")" = 1

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
