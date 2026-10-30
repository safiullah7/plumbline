#!/usr/bin/env bash
# The security rules of /plumbline:signoff as a report, for the build skill and the
# lead: the recorded level (.plumbline security= and the dev plan's Security level:
# line, the higher wins), the required level (minus what the user waived), the
# attack plan's rows with their Checked cells, each attack test's result, the
# secrets scan, the open critical and high findings, the independent-pass state,
# every gap, and notes that are not gaps (a failing own attack that a finding
# covers, a generic runner passed by exit status). The rules are security_gaps in lib.sh, the same function
# signoff-check.sh calls, so the two never disagree.
#   security-check.sh [--no-run]
# It runs the attack tests (ac-check.sh per surface) unless --no-run, which skips
# only that run (for a quick look, and for tests of the parsing). At level none it
# prints that and runs nothing.
# Exit 0 = no gaps, 1 = at least one gap, 2 = usage.
source "$(dirname "${0//\\//}")/lib.sh"
run=""
case "${1:-}" in
  "") ;;
  --no-run) run=--no-run ;;
  *) echo "usage: security-check.sh [--no-run]" >&2; exit 2 ;;
esac
(( $# <= 1 )) || { echo "usage: security-check.sh [--no-run]" >&2; exit 2; }
dir=$(phase_dir) || { echo "Security check: no active phase (.claude/current-phase is missing)."; exit 1; }
rel=$(phase_rel)
US=$'\037'

lvl=$(security_level)
echo "Security check: $rel"
kt=$(security_key_token); pt=$(security_plan_token)
echo "Recorded level: $lvl (.plumbline: ${kt:-none}, dev-plan.md: ${pt:-none})"
if [[ "$lvl" == none ]]; then
  echo "Required: none. Nothing to check at level none."
  exit 0
fi
echo "Required: $(security_required | sed 's/ /, /g') (parts the user hasn't waived)"

echo "Attack plan:"
n=0
while IFS=$US read -r kind a b c d e; do
  if [[ "$kind" == gap ]]; then echo "  unreadable: $a"; continue; fi
  n=$((n + 1)); echo "  $a [${b:-no surface}] Checked: ${e:-empty}"
done < <(security_rows plan)
(( n > 0 )) || echo "  (no rows)"
m=0
while IFS=$US read -r kind a b c d e; do
  [[ "$kind" == row ]] && m=$((m + 1))
done < <(security_rows own)
echo "Own attacks: $m"

export SECURITY_RESULTS_FILE
SECURITY_RESULTS_FILE=$(mktemp); trap 'rm -f "$SECURITY_RESULTS_FILE"' EXIT
gaps=$(security_gaps $run)

echo "Attack tests:"
if [[ -n "$run" ]]; then
  echo "  not run (--no-run)"
elif [[ -s "$SECURITY_RESULTS_FILE" ]]; then
  notes=""
  while IFS=$US read -r id s res note; do
    echo "  $id [${s:-default surface}]: ${res:-no result}"
    [[ -n "$note" ]] && notes="$notes  $note"$'\n'
  done < "$SECURITY_RESULTS_FILE"
  # Not gaps: an own attack failing because a finding covers it, a generic runner's exit status.
  [[ -n "$notes" ]] && { echo "Notes:"; printf '%s' "$notes"; }
else
  echo "  none ran"
fi

hits=$(secrets_scan); rc=$?
if (( rc == 2 )); then echo "Secrets scan: could not run (no base branch)"
elif [[ -z "$hits" ]]; then echo "Secrets scan: clean"
else echo "Secrets scan: $(grep -c . <<<"$hits") hit(s): $(paste -sd' ' - <<<"$hits")"
fi

open=""
while IFS=$US read -r kind a b c d e; do
  [[ "$kind" == row ]] || continue
  sev="$b"; st="$d"
  [[ ("$sev" == critical || "$sev" == high) && "$st" != verified ]] && open="$open  #${a#\#} $sev ($st): $c"$'\n'
done < <(security_rows findings)
if [[ -n "$open" ]]; then echo "Open critical and high findings:"; printf '%s' "$open"; else echo "Open critical and high findings: none"; fi
echo "Independent pass: $(security_independent_state || true)"

if [[ -z "$gaps" ]]; then
  echo "Security check: no gaps."
  exit 0
fi
echo "Security check: $(grep -c . <<<"$gaps") gap(s):"
sed 's/^/- /' <<<"$gaps"
exit 1
