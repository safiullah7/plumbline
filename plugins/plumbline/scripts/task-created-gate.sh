#!/usr/bin/env bash
# TaskCreated: during Build, every task names the AC IDs it delivers, so the
# completion gate can run their tests. Coordination work with no AC is allowed
# with a [chore] prefix. Lead-created tasks carry no teammate name, so this gates
# every creation. Exit 2 = refuse (Claude Code deletes the task) + feedback.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

build_active || exit 0
require_jq
subject=$(jqr '.task_subject // empty' <<<"$input")

[[ "$subject" =~ AC-[0-9]+-[0-9]+ ]] && exit 0
shopt -s nocasematch
[[ "$subject" =~ ^[[:space:]]*\[chore\] ]] && exit 0

echo "Task gate: \"$subject\" names no AC IDs. Start the subject with the ACs it delivers, e.g. \"[AC-03-004 AC-03-005] Reschedule API\", or with \"[chore]\" for coordination work that delivers no AC." >&2
exit 2
