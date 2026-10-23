#!/usr/bin/env bash
# TaskCompleted: a teammate's task is done only when it names its AC IDs and
# typecheck, lint and those AC-tagged tests pass. Exit 2 = refuse + feedback.
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
log=$(mktemp)
fail() { echo "Task gate: $1" >&2; tail -n 30 "$log" >&2; exit 2; }

cd "$PROJECT_DIR" || exit 0
[[ -n "$ids" ]] || fail "the task subject has no AC IDs. Ask the lead to prefix it, e.g. [AC-03-004]."
if [[ -n "$TYPECHECK" ]]; then eval "$TYPECHECK" >"$log" 2>&1 || fail "typecheck failed."; fi
if [[ -n "$LINT" ]]; then eval "$LINT" >"$log" 2>&1 || fail "lint failed."; fi
if [[ -n "$TEST_AC" ]]; then
  eval "$TEST_AC \"\$ids\"" >"$log" 2>&1 \
    || fail "tests for $ids failed or none exist. Name tests after their AC IDs."
fi
exit 0
