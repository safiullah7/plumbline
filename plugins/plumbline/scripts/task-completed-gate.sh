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

# The checks run through run_checks in lib.sh. Their commands are overridable per
# repo through PLUMBLINE_TYPECHECK, PLUMBLINE_LINT and PLUMBLINE_TEST_AC in the env
# block of .claude/settings.json. Set one to "" to skip that check.
subject=$(jqr '.task_subject // empty' <<<"$input")
ids=$(grep -oE 'AC-[0-9]+-[0-9]+' <<<"$subject" | sort -u | paste -sd'|' -)
chore=""
shopt -s nocasematch
[[ -z "$ids" && "$subject" =~ ^[[:space:]]*\[chore\] ]] && chore=1
shopt -u nocasematch
trap 'rm -f "${RUN_CHECKS_LOG:-}"' EXIT
fail() {
  echo "Task gate: $1" >&2
  [[ -n "${RUN_CHECKS_LOG:-}" ]] && tail -n 30 "$RUN_CHECKS_LOG" >&2
  exit 2
}

cd "$PROJECT_DIR" || exit 0
[[ -n "$ids" || -n "$chore" ]] || fail "the task subject has no AC IDs. Ask the lead to prefix it, e.g. [AC-03-004]."
if ! run_checks "$ids"; then   # a [chore] has no IDs, so its tests are skipped
  case "$RUN_CHECKS_FAILED" in
    typecheck) fail "typecheck failed." ;;
    lint)      fail "lint failed." ;;
    *)         fail "tests for $ids failed or none exist. Name tests after their AC IDs." ;;
  esac
fi
[[ -n "${PLUMBLINE_HOOK_TIMING:-}" && -n "$RUN_CHECKS_TIMING" ]] && echo "Task gate passed: $RUN_CHECKS_TIMING" >&2
exit 0
