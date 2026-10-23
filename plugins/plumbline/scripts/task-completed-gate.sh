#!/usr/bin/env bash
# TaskCompleted: a teammate's task is done only when it names its AC IDs and
# typecheck, lint and those AC-tagged tests pass. A [chore] task has no AC tests,
# so it needs typecheck and lint only. Exit 2 = refuse + feedback.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

build_active || exit 0
require_jq
who=$(jqr '.teammate_name // empty' <<<"$input")
[[ -z "$who" ]] && exit 0

# Commands are overridable per repo through the env block in .claude/settings.json.
# Set one to "" to skip that check.
TYPECHECK="${PLUMBLINE_TYPECHECK-npm run -s typecheck}"
LINT="${PLUMBLINE_LINT-npm run -s lint}"
TEST_AC="${PLUMBLINE_TEST_AC-npm run -s test:ac --}"

subject=$(jqr '.task_subject // empty' <<<"$input")
ids=$(grep -oE 'AC-[0-9]+-[0-9]+' <<<"$subject" | sort -u | paste -sd'|' -)
chore=""
shopt -s nocasematch
[[ -z "$ids" && "$subject" =~ ^[[:space:]]*\[chore\] ]] && chore=1
shopt -u nocasematch
log=$(mktemp)
timing=""
fail() { echo "Task gate: $1" >&2; tail -n 30 "$log" >&2; exit 2; }
run() { # label command
  local t0=$SECONDS
  eval "$2" >"$log" 2>&1 || return 1
  timing="$timing${timing:+ · }$1 $((SECONDS - t0))s"
}

cd "$PROJECT_DIR" || exit 0
[[ -n "$ids" || -n "$chore" ]] || fail "the task subject has no AC IDs. Ask the lead to prefix it, e.g. [AC-03-004]."
if [[ -n "$TYPECHECK" ]]; then run typecheck "$TYPECHECK" || fail "typecheck failed."; fi
if [[ -n "$LINT" ]]; then run lint "$LINT" || fail "lint failed."; fi
if [[ -n "$TEST_AC" && -z "$chore" ]]; then
  run tests "$TEST_AC \"\$ids\"" \
    || fail "tests for $ids failed or none exist. Name tests after their AC IDs."
fi
[[ -n "${PLUMBLINE_HOOK_TIMING:-}" && -n "$timing" ]] && echo "Task gate passed: $timing" >&2
exit 0
