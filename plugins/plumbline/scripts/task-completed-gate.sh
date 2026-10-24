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
# block of .claude/settings.json. Set one to "" to skip that check. Otherwise the
# commands come from the teammate's surface: the Surface column (4) of its row in
# the dev plan's Team table names a row of docs/product/project.md. A plan without
# that column, or a row with an empty cell, passes no surface: fine without a
# profile (the npm defaults, as in v0.3) or with a one-row profile, refused when
# the profile lists several, except for a [chore], which then runs every
# surface's typecheck and lint.
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
failed() { # the surface, for a [chore] that runs them all
  case "$RUN_CHECKS_FAILED" in
    typecheck) fail "typecheck failed${1:+ for surface $1}." ;;
    lint)      fail "lint failed${1:+ for surface $1}." ;;
    surface)
      profile_surface "$surface" >/dev/null
      if [[ $? == 2 ]]; then
        fail "$who has no Surface in the dev plan's Team table and the profile lists several ($(surface_list)); ask the lead to add one, or tag coordination work [chore]"
      fi
      fail "$who's Surface \"$surface\" in the dev plan's Team table isn't a surface in docs/product/project.md, which lists: $(surface_list); ask the lead to fix one of them" ;;
    *) [[ -n "$RUN_CHECKS_ERROR" ]] && fail "$RUN_CHECKS_ERROR"
       fail "tests for $ids failed or none exist. Name tests after their AC IDs." ;;
  esac
}

cd "$PROJECT_DIR" || exit 0
[[ -n "$ids" || -n "$chore" ]] || fail "the task subject has no AC IDs. Ask the lead to prefix it, e.g. [AC-03-004]."
surface=""
if dir=$(phase_dir); then
  surface=$(md_table "$dir/dev-plan.md" Team 2>/dev/null \
    | awk -F'\t' -v w="$who" '$1 == w { print $4; exit }' | tr -d '`[:space:]')
fi
if ! run_checks "$ids" "$surface"; then   # a [chore] has no IDs, so its tests are skipped
  [[ -n "$chore" && "$RUN_CHECKS_FAILED" == surface && -z "$surface" ]] || failed
  # A [chore] with no surface is coordination work: every surface's checks.
  surfaces=() timing=""
  while IFS= read -r s; do surfaces+=("$s"); done < <(project_surfaces)
  for s in "${surfaces[@]}"; do
    rm -f "$RUN_CHECKS_LOG"
    run_checks "" "$s" || failed "$s"
    timing="$timing${timing:+ · }$s: ${RUN_CHECKS_TIMING:-nothing to run}"
  done
  RUN_CHECKS_TIMING="$timing"
fi
[[ -n "${PLUMBLINE_HOOK_TIMING:-}" && -n "$RUN_CHECKS_TIMING" ]] && echo "Task gate passed: $RUN_CHECKS_TIMING" >&2
exit 0
