#!/usr/bin/env bash
# Prints the dev plan's tasks for the lead to create in the shared task list, one
# line per task in plan order (the lead's [chore] lines included):
#   owner<TAB>subject<TAB>blocked-by labels (comma-separated)<TAB>done-when<TAB>label
#   plan-tasks.sh [--dir <feature dir>]
# The feature dir defaults to the active phase. The subject is the task line without
# its "- " and its rating, label included ("[AC-02-030 SEC-02-007] B4: Status changes").
# A task's label is the "B4:" written right after the brackets, or T<n> when it has
# none, where n is the task's line number in this output (so T3 is the third line).
# "Blocked by:" lines name labels. Exit 0 = every task printed; 1 = the plan needs a
# fix (a duplicate or unknown label, a bad Blocked by entry, a subject the task gate
# would refuse, no tasks), with the reason on stderr and nothing on stdout; 2 = usage.
source "$(dirname "${0//\\//}")/lib.sh"
source "$(dirname "${0//\\//}")/tasks-lib.sh"

dir=""
while (( $# )); do
  case "$1" in
    --dir)   (( $# >= 2 )) || { echo 'usage: plan-tasks.sh [--dir <feature dir>]' >&2; exit 2; }; dir="$2"; shift 2 ;;
    --dir=*) dir="${1#*=}"; shift ;;
    *)       echo 'usage: plan-tasks.sh [--dir <feature dir>]' >&2; exit 2 ;;
  esac
done
if [[ -z "$dir" ]]; then
  dir=$(phase_dir) || { echo "plan-tasks: no active phase (.claude/current-phase is missing); pass --dir <feature dir>." >&2; exit 1; }
fi
plan="$dir/dev-plan.md"
[[ -f "$plan" ]] || { echo "plan-tasks: $plan is missing." >&2; exit 1; }

recs=$(tasks_parse "$plan") || { echo "plan-tasks: fix the labels in $plan and run it again." >&2; exit 1; }
[[ -n "$recs" ]] || { echo "plan-tasks: $plan has no tasks under \"## Tasks\" (### <owner> sections of \"- [AC-...] Title (RATING)\" lines)." >&2; exit 1; }

out="" bad=0
while IFS=$'\037' read -r n owner label ids subject rating blocked done title block; do
  if ! task_subject_ok "$subject"; then
    echo "plan-tasks: task $n (\"$subject\") names no AC or SEC IDs and doesn't start with [chore]; the task gate would refuse it." >&2
    bad=1
  fi
  out+="$owner"$'\t'"${subject//$'\t'/ }"$'\t'"$blocked"$'\t'"$done"$'\t'"$label"$'\n'
done <<<"$recs"
(( bad )) && exit 1
printf '%s' "$out"
