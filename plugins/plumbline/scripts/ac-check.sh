#!/usr/bin/env bash
# The task gate's checks as a script, for work the TaskCompleted hook never sees
# (subagents, Quick changes): typecheck, lint and the tests named after the given
# AC or SEC IDs, through run_checks in lib.sh, so both pass or fail on the same commands.
#   ac-check.sh "AC-03-001|AC-03-002|SEC-03-001" [--surface <surface>]
# --surface names a row of docs/product/project.md and picks that surface's
# Typecheck, Lint and AC tests commands (the env vars still win); without it,
# the profile's only row is used, or the npm defaults when there is no profile.
# A pass prints the adapter's per-ID lines (and the generic adapter's warning),
# then "ac-check: pass (<timing>)".
# Exit 0 = every check passed, 1 = a check failed (its per-ID lines and last 30 log lines go to
# stderr) or there is no AC test command for the surface, 2 = usage, or a
# surface the profile doesn't list, or no surface when it lists several.
source "$(dirname "${0//\\//}")/lib.sh"
usage() { echo 'usage: ac-check.sh "<AC or SEC IDs>" [--surface <surface>]' >&2; exit 2; }

args="" surface=""
while (( $# )); do
  case "$1" in
    --surface)   (( $# >= 2 )) || usage; surface="$2"; shift 2 ;;
    --surface=*) surface="${1#*=}"; shift ;;
    -*)          usage ;;
    *)           args="$args $1"; shift ;;
  esac
done
# The same IDs the task gate would take from a task subject (AC- or SEC-).
ids=$(grep -oE '(AC|SEC)-[0-9]+-[0-9]+' <<<"$args" | sort -u | paste -sd'|' -)
[[ -n "$ids" ]] || usage

# A surface the profile can't resolve would run some other surface's commands.
surface_error() {
  profile_surface "$surface" >/dev/null
  if [[ $? == 2 ]]; then
    echo "ac-check: several surfaces in docs/product/project.md; pass --surface <one of: $(surface_list)>" >&2
  else
    echo "ac-check: unknown surface \"$surface\"; the profile lists: $(surface_list)" >&2
  fi
  exit 2
}

# Unlike the task gate, a pass here has to mean the tests ran: an empty AC test
# command (PLUMBLINE_TEST_AC="", or an AC tests cell of none) is refused, and so
# is an empty AC tests cell. Typecheck and lint may still be skipped.
test_ac=$(check_command PLUMBLINE_TEST_AC "$surface" "npm run -s test:ac --"); rc=$?
case "$rc" in
  0) ;;
  3) echo "ac-check: $(ac_command_missing "$surface")" >&2; exit 1 ;;
  *) surface_error ;;
esac
if [[ -z "$test_ac" ]]; then
  echo "ac-check: no AC test command configured" >&2
  exit 1
fi

trap 'rm -f "${RUN_CHECKS_LOG:-}"' EXIT
if run_checks "$ids" "$surface"; then
  tr -d '\r' < "$RUN_CHECKS_LOG" | grep -E '^((AC|SEC)-[0-9]+-[0-9]+: |generic: )'
  echo "ac-check: pass${RUN_CHECKS_TIMING:+ ($RUN_CHECKS_TIMING)}"
  exit 0
fi
[[ "$RUN_CHECKS_FAILED" == surface ]] && surface_error
what="$RUN_CHECKS_FAILED"
[[ "$what" == tests ]] && what="tests for $ids"
echo "ac-check: $what failed" >&2
# The adapter prints its per-ID lines first; keep them when the tail cuts them off.
if [[ "$RUN_CHECKS_FAILED" == tests ]] && (( $(wc -l < "$RUN_CHECKS_LOG") > 30 )); then
  tr -d '\r' < "$RUN_CHECKS_LOG" | grep -E '^((AC|SEC)-[0-9]+-[0-9]+: |generic: )' >&2
fi
tail -n 30 "$RUN_CHECKS_LOG" >&2
exit 1
