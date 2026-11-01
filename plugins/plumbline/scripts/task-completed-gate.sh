#!/usr/bin/env bash
# TaskCompleted: a teammate's task is done only when it names its AC IDs (SEC IDs
# count too) and those tests pass. Typecheck and lint run once per workstream (the
# lead's ac-check at acceptance), not per task, so a task with IDs checks its tests
# only; PLUMBLINE_TASK_CHECKS=full brings typecheck and lint back for every task. A
# [chore] task has no AC tests, so it keeps typecheck and lint. Exit 2 = refuse +
# feedback. A task completed by a teammate with no row in the dev plan's Team table
# (the lead's chores, e.g. L0) skips the checks: the lead runs the full checks at
# workstream acceptance. On a pass, a payload with team_name also names the
# teammates this completion unblocked, in a systemMessage. Note that a systemMessage
# is shown to the user, not to an agent: it cannot wake anyone itself.
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
# surface's typecheck and lint. Under the tests-only default both are skipped even
# when PLUMBLINE_TYPECHECK or PLUMBLINE_LINT is set.
subject=$(jqr '.task_subject // empty' <<<"$input")
ids=$(grep -oE '(AC|SEC)-[0-9]+-[0-9]+' <<<"$subject" | sort -u | paste -sd'|' -)
chore=""
shopt -s nocasematch
[[ -z "$ids" && "$subject" =~ ^[[:space:]]*\[chore\] ]] && chore=1
shopt -u nocasematch
[[ -n "$ids" && "${PLUMBLINE_TASK_CHECKS:-}" != full ]] && export PLUMBLINE_TYPECHECK= PLUMBLINE_LINT=
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
surface="" teamrows="" teamrow=""
if dir=$(phase_dir); then
  teamrows=$(md_table "$dir/dev-plan.md" Team 2>/dev/null)
  teamrow=$(awk -F'\t' -v w="$who" '$1 == w { print; exit }' <<<"$teamrows")
  surface=$(awk -F'\t' '{ print $4 }' <<<"$teamrow" | tr -d '`[:space:]')
fi
# The lead (teammate `lead`, no Team row) completes its chores, like L0, with nothing
# to check here: it runs the full checks at workstream acceptance. Any other name
# without a Team row is checked as before, so a misnamed engineer can't skip tests.
if [[ -n "$teamrows" && -z "$teamrow" && "$who" == lead ]]; then
  ids="" chore=1
else
  [[ -n "$ids" || -n "$chore" ]] || fail "the task subject has no AC IDs. Ask the lead to prefix it, e.g. [AC-03-004]."
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
fi

# Who did this completion unblock? Pending tasks that list it in blockedBy and have
# nothing else open (this task counts as done, whatever its file says yet). One
# message per owner, never to the teammate who just finished.
team=$(jqr '.team_name // empty' <<<"$input")
tid=$(jqr '.task_id // empty' <<<"$input")
if [[ -n "$team" && -n "$tid" ]] && tdir=$(team_dir_for "$team"); then
  msg=""
  while IFS= read -r owner; do
    [[ -n "$owner" && "$owner" != "$who" ]] || continue
    subjects=$(ready_tasks "$tdir" "$owner" "$tid" | awk -F'\t' -v t="$tid" '
      $3 == "pending" { n = split($4, b, ","); for (i = 1; i <= n; i++) if (b[i] == t) { s = s (s == "" ? "" : ", ") $5; break } }
      END { print s }')
    [[ -n "$subjects" ]] && msg+="${msg:+ }You unblocked $owner's $subjects: SendMessage $owner now."
  done < <(team_tasks "$tdir" | awk -F'\t' -v t="$tid" '$2 != "" && !seen[$2]++ { n = split($4, b, ","); for (i = 1; i <= n; i++) if (b[i] == t) { print $2; break } }')
  [[ -n "$msg" ]] && jq -n --arg m "$msg" '{systemMessage: $m}'
fi
exit 0
