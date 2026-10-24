#!/usr/bin/env bash
# The task gate's checks as a script, for work the TaskCompleted hook never sees
# (subagents, Quick changes): typecheck, lint and the tests named after the given
# AC IDs, through run_checks in lib.sh, so both pass or fail on the same commands.
#   ac-check.sh "AC-03-001|AC-03-002" [--surface <surface>]
# --surface names a row of docs/product/project.md and picks that surface's
# Typecheck, Lint and AC tests commands (the env vars still win); without it,
# the profile's only row is used, or the npm defaults when there is no profile.
# Exit 0 = every check passed, 1 = a check failed (its last 30 log lines go to
# stderr) or there is no AC test command for the surface, 2 = usage.
source "$(dirname "${0//\\//}")/lib.sh"
usage() { echo 'usage: ac-check.sh "<AC IDs>" [--surface <surface>]' >&2; exit 2; }

args="" surface=""
while (( $# )); do
  case "$1" in
    --surface)   (( $# >= 2 )) || usage; surface="$2"; shift 2 ;;
    --surface=*) surface="${1#*=}"; shift ;;
    -*)          usage ;;
    *)           args="$args $1"; shift ;;
  esac
done
# The same IDs the task gate would take from a task subject.
ids=$(grep -oE 'AC-[0-9]+-[0-9]+' <<<"$args" | sort -u | paste -sd'|' -)
[[ -n "$ids" ]] || usage

# Unlike the task gate, a pass here has to mean the tests ran: an empty AC test
# command (PLUMBLINE_TEST_AC="", or an empty AC tests cell for this surface) is
# refused. Typecheck and lint may still be skipped.
if [[ -z "$(check_command PLUMBLINE_TEST_AC "$surface" "npm run -s test:ac --")" ]]; then
  echo "ac-check: no AC test command configured" >&2
  exit 1
fi

trap 'rm -f "${RUN_CHECKS_LOG:-}"' EXIT
if run_checks "$ids" "$surface"; then
  echo "ac-check: pass${RUN_CHECKS_TIMING:+ ($RUN_CHECKS_TIMING)}"
  exit 0
fi
what="$RUN_CHECKS_FAILED"
[[ "$what" == tests ]] && what="tests for $ids"
echo "ac-check: $what failed" >&2
tail -n 30 "$RUN_CHECKS_LOG" >&2
exit 1
