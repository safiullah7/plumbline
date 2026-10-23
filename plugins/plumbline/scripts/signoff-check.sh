#!/usr/bin/env bash
# The /plumbline:signoff gap check as a script, so a phase can't be talked past a
# gap: every AC has a passing test in test-plan.md, the QA verdict is PASS with no
# open high or critical bug, no open product finding or high design finding, no
# OPEN or ESCALATED question, and every sign-off box is ticked except the PR and
# merge lines. Exits 1 and lists each gap, or exits 0 when there are none.
source "$(dirname "${0//\\//}")/lib.sh"
dir=$(phase_dir) || { echo "Signoff check: no active phase (.claude/current-phase is missing)."; exit 1; }
rel=$(phase_rel)
gaps=()

# A phase doc that doesn't exist can't pass its checks; say so instead of
# letting an empty file list slip through.
for f in acceptance-criteria.md test-plan.md qa-report.md signoff.md; do
  [[ -f "$dir/$f" ]] || gaps+=("$f is missing")
done

passing=$(md_table "$dir/test-plan.md" Traceability 2>/dev/null \
  | awk -F'\t' 'tolower($4) ~ /pass/ { print $1 }' | grep -oE 'AC-[0-9]+-[0-9]+')
for id in $(md_table "$dir/acceptance-criteria.md" 2>/dev/null | awk -F'\t' '$1 ~ /^AC-[0-9]+-[0-9]+$/ { print $1 }' | sort -u); do
  grep -qx "$id" <<<"$passing" || gaps+=("$id has no passing test in test-plan.md")
done

verdict=$(grep -m1 -iE '^Verdict:' "$dir/qa-report.md" 2>/dev/null | tr -d '\r' | sed -E 's/^[Vv]erdict:[[:space:]]*//')
[[ "${verdict^^}" == PASS ]] || gaps+=("QA verdict is ${verdict:-missing}, not PASS (qa-report.md)")
while IFS= read -r b; do [[ -n "$b" ]] && gaps+=("open bug $b (qa-report.md)"); done < <(
  md_table "$dir/qa-report.md" Bugs 2>/dev/null | awk -F'\t' '
    $1 != "" && toupper($4) !~ /^(FIXED|VERIFIED|WONTFIX|CLOSED)$/ && tolower($3) ~ /^(high|critical)$/ { print $1 " (" tolower($3) "): " $5 }')

closed='^(FIXED|RESOLVED|CLOSED|WONTFIX|VERIFIED|DONE)$'
while IFS= read -r f; do [[ -n "$f" ]] && gaps+=("open product finding $f (signoff.md)"); done < <(
  md_table "$dir/signoff.md" "Product findings" 2>/dev/null | awk -F'\t' -v c="$closed" '$1 != "" && toupper($4) !~ c { print "#" $1 ": " $3 }')
while IFS= read -r f; do [[ -n "$f" ]] && gaps+=("open high design finding $f (signoff.md)"); done < <(
  md_table "$dir/signoff.md" "Design findings" 2>/dev/null | awk -F'\t' -v c="$closed" '$1 != "" && tolower($4) == "high" && toupper($5) !~ c { print "#" $1 ": " $3 }')

while IFS= read -r f; do [[ -n "$f" ]] && gaps+=("$f (questions.md)"); done < <(
  md_table "$dir/questions.md" 2>/dev/null | awk -F'\t' 'toupper($6) ~ /^(OPEN|ESCALATED)$/ { print toupper($6) " question #" $1 ": " substr($4, 1, 120) }')

while IFS= read -r line; do
  [[ -n "$line" ]] && gaps+=("unticked sign-off box: $(sed -E 's/^[[:space:]]*- \[ \][[:space:]]*//' <<<"$line") (signoff.md)")
done < <({ tr -d '\r' < "$dir/signoff.md"; } 2>/dev/null | grep -E '^[[:space:]]*- \[ \]' | grep -viE 'phase pr|merged')

if (( ${#gaps[@]} == 0 )); then
  echo "Signoff check: no gaps in $rel."
  exit 0
fi
echo "Signoff check: ${#gaps[@]} gap(s) in $rel:"
printf -- '- %s\n' "${gaps[@]}"
exit 1
