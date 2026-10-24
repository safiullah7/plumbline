#!/usr/bin/env bash
# The /plumbline:signoff gap check as a script, so a phase can't be talked past a
# gap: every AC has a passing test in test-plan.md, the QA verdict is PASS with no
# open high or critical bug, accessibility results (or a waiver) where there's a
# UI, every evidence kind the feature's surfaces require (or a waiver), no open
# product finding or high design finding, no OPEN or ESCALATED question, and every
# sign-off box is ticked except the PR and merge lines. Exits 1 and lists each
# gap, or exits 0 when there are none.
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
[[ "$(tr '[:lower:]' '[:upper:]' <<<"$verdict")" == PASS ]] || gaps+=("QA verdict is ${verdict:-missing}, not PASS (qa-report.md)")
while IFS= read -r b; do [[ -n "$b" ]] && gaps+=("open bug $b (qa-report.md)"); done < <(
  md_table "$dir/qa-report.md" Bugs 2>/dev/null | awk -F'\t' '
    $1 != "" && toupper($4) !~ /^(FIXED|VERIFIED|WONTFIX|CLOSED)$/ && tolower($3) ~ /^(high|critical)$/ { print $1 " (" tolower($3) "): " $5 }')

# Accessibility: serious or critical violations block, and so do missing
# results, unless the scan was explicitly waived (the tools are optional).
a11y=$(md_table "$dir/qa-report.md" Accessibility 2>/dev/null)
while IFS=$'\t' read -r screen width crit ser _; do
  [[ -n "$screen" ]] || continue
  if ! [[ "$crit" =~ ^[0-9]+$ && "$ser" =~ ^[0-9]+$ ]]; then
    gaps+=("accessibility results for $screen at $width aren't counts (scan not run?) (qa-report.md)")
  elif (( crit + ser > 0 )); then
    gaps+=("accessibility: $screen at $width has $crit critical and $ser serious violation(s) (qa-report.md)")
  fi
done <<<"$a11y"
# A waiver line counts only when it's filled in: no <placeholder> left and an
# "(approved by <name>)" ending, so the template's example line waives nothing.
accessibility_waived() {
  { tr -d '\r' < "$dir/qa-report.md"; } 2>/dev/null | grep -iE '^Accessibility waived:' \
    | grep -v '<[^>]*>' | grep -qiE '\(approved by [^)]*[^) ][^)]*\)[[:space:]]*$'
}
# Text as an ERE that matches only itself, for names put into a pattern.
ere_quote() { sed 's/[][\.*^$+?(){}|]/\\&/g' <<<"$1"; }
# "Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)", the dash
# also "—" or ":", filled in the same way as the accessibility waiver.
evidence_waived() { # kind surface
  local k s
  k=$(ere_quote "$1"); s=$(ere_quote "$2")
  { tr -d '\r' < "$dir/qa-report.md"; } 2>/dev/null | grep -v '<[^>]*>' \
    | grep -qiE "^Evidence waived:[[:space:]]*$k[[:space:]]*\\($s\\)[[:space:]]*(-|—|:)[[:space:]]*[^[:space:]].*\\(approved by [^)]*[^) ][^)]*\\)[[:space:]]*\$"
}

# Features with surfaces= in .plumbline (v0.4b) are checked by surface; legacy
# and v0.4a features keep the v0.3 rule, which keys accessibility off ux.md.
surfaces=$(feature_meta surfaces)
if [[ -z "$surfaces" ]]; then
  screens=$(md_table "$dir/ux.md" "Screen inventory" 2>/dev/null | awk -F'\t' '$1 != ""' | grep -c .)
  if [[ -z "$a11y" && "$screens" -gt 0 ]] && ! accessibility_waived; then
    gaps+=("no accessibility results for the $screens screen(s) in ux.md: run the scan, or ask the user to waive it (the build skill writes the line) (qa-report.md)")
  fi
else
  # Evidence rows with Result pass, as "kind<TAB>surface"; kind and result in any case.
  passed=$(md_table "$dir/qa-report.md" Evidence 2>/dev/null \
    | awk -F'\t' '$1 != "" && tolower($4) == "pass" { print tolower($1) "\t" $2 }')
  recorded=$(md_table "$dir/qa-report.md" Evidence 2>/dev/null | awk -F'\t' '{ print tolower($1) "\t" $2 "\t" tolower($4) }')
  seen="," axe_for="" checklist_for=""
  IFS=, read -r -a snames <<<"$surfaces"
  for s in "${snames[@]}"; do
    s=$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$s")
    [[ -n "$s" && "$seen" != *",$s,"* ]] || continue
    seen="$seen$s,"
    if ! kind=$(surface_kind "$s"); then
      gaps+=("unknown surface \"$s\" in .plumbline surfaces=: a surface is web-ui, mobile-ui, desktop-ui, api, service, cli, library, data, ai or infra, or <kind>-<name>; ask the user to correct it")
      continue
    fi
    # Required evidence kinds by surface kind (dev plan §6.4, the table rules).
    case "$kind" in
      web-ui)     need="screenshots axe journeys"; axe_for="$axe_for${axe_for:+, }$s" ;;
      mobile-ui)  need="screenshots flow-tests checklist"; checklist_for="$checklist_for${checklist_for:+, }$s" ;;
      desktop-ui) need="screenshots checklist"; checklist_for="$checklist_for${checklist_for:+, }$s" ;;
      api)        need="contract authz negative transcripts" ;;
      service)    need="job-tests failure-cases" ;;
      cli)        need="golden-output" ;;
      library)    need="doc-examples api-diff" ;;
      data)       need="sample-run idempotency" ;;
      ai)         need="eval-set injection" ;;
      infra)      need="plan-output" ;;
    esac
    for k in $need; do
      grep -qxF "$(printf '%s\t%s' "$k" "$s")" <<<"$passed" && continue
      evidence_waived "$k" "$s" && continue
      # The scan the user waived is this evidence too: don't ask twice.
      [[ "$k" == axe || "$k" == checklist ]] && accessibility_waived && continue
      got=$(awk -F'\t' -v k="$k" -v s="$s" '$1 == k && $2 == s && $3 != "" { print $3 }' <<<"$recorded" | sort -u | paste -sd, -)
      gaps+=("no passing $k evidence for $s${got:+ (recorded: $got)}: record it in qa-report.md's Evidence table, or ask the user to waive it; the build skill writes the line (qa-report.md)")
    done
  done
  # Accessibility by surface: web-ui needs axe rows, mobile-ui and desktop-ui
  # checklist rows; surfaces with no UI are exempt. A row without a Method is a
  # v0.3 row, which was always axe. One Accessibility waiver covers both.
  methods=$(awk -F'\t' '$1 != "" { m = tolower($8); print (m == "" ? "axe" : m) }' <<<"$a11y")
  if [[ -n "$axe_for" ]] && ! grep -qx axe <<<"$methods" && ! accessibility_waived; then
    gaps+=("no axe accessibility results for $axe_for: run the scan, or ask the user to waive it (the build skill writes the line) (qa-report.md)")
  fi
  if [[ -n "$checklist_for" ]] && ! grep -qx checklist <<<"$methods" && ! accessibility_waived; then
    gaps+=("no checklist accessibility results for $checklist_for: fill in qa/a11y-checklist.tsv and run qa-summary.sh, or ask the user to waive it (the build skill writes the line) (qa-report.md)")
  fi
fi

closed='^(FIXED|RESOLVED|CLOSED|WONTFIX|VERIFIED|DONE)$'
while IFS= read -r f; do [[ -n "$f" ]] && gaps+=("open product finding $f (signoff.md)"); done < <(
  md_table "$dir/signoff.md" "Product findings" 2>/dev/null | awk -F'\t' -v c="$closed" '$1 != "" && toupper($4) !~ c { print "#" $1 ": " $3 }')
while IFS= read -r f; do [[ -n "$f" ]] && gaps+=("open high design finding $f (signoff.md)"); done < <(
  md_table "$dir/signoff.md" "Design findings" 2>/dev/null | awk -F'\t' -v c="$closed" '$1 != "" && tolower($4) == "high" && toupper($5) !~ c { print "#" $1 ": " $3 }')

while IFS= read -r f; do [[ -n "$f" ]] && gaps+=("$f (questions.md)"); done < <(
  md_table "$dir/questions.md" 2>/dev/null | awk -F'\t' 'toupper($6) ~ /^(OPEN|ESCALATED)$/ { print toupper($6) " question #" $1 ": " substr($4, 1, 120) }')

while IFS= read -r line; do
  [[ -n "$line" ]] && gaps+=("unticked sign-off box: $(sed -E 's/^[[:space:]]*- \[ \][[:space:]]*//' <<<"$line") (signoff.md)")
done < <({ tr -d '\r' < "$dir/signoff.md"; } 2>/dev/null | grep -E '^[[:space:]]*- \[ \]' | grep -viE '(phase|feature) pr|merged')

if (( ${#gaps[@]} == 0 )); then
  echo "Signoff check: no gaps in $rel."
  exit 0
fi
echo "Signoff check: ${#gaps[@]} gap(s) in $rel:"
printf -- '- %s\n' "${gaps[@]}"
exit 1
