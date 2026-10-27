#!/usr/bin/env bash
# The /plumbline:signoff gap check as a script, so a phase can't be talked past a
# gap: every AC has a passing test in test-plan.md, the QA verdict is PASS with no
# open high or critical bug, the one evidence kind each of the feature's surfaces
# requires (or a waiver), no open product finding or high design finding, no OPEN
# or ESCALATED question, and every sign-off box is ticked except the PR and merge
# lines (and the "Design verification" box of old features). Required evidence per
# surface: web-ui and desktop-ui journeys, mobile-ui flow-tests, api transcripts,
# service job-tests, cli golden-output, library doc-examples, data sample-run, ai
# eval-set, infra plan-output. Features without surfaces= have no evidence rule.
# Exits 1 and lists each gap, or exits 0 when there are none.
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

# Text as an ERE that matches only itself, for names put into a pattern.
ere_quote() { sed 's/[][\.*^$+?(){}|]/\\&/g' <<<"$1"; }
# "Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)", the dash
# also "—" or ":". A waiver line counts only when it's filled in: no <placeholder>
# left and an "(approved by <name>)" ending, so the template's example waives nothing.
evidence_waived() { # kind surface
  local k s
  k=$(ere_quote "$1"); s=$(ere_quote "$2")
  { tr -d '\r' < "$dir/qa-report.md"; } 2>/dev/null | grep -v '<[^>]*>' \
    | grep -qiE "^Evidence waived:[[:space:]]*$k[[:space:]]*\\($s\\)[[:space:]]*(-|—|:)[[:space:]]*[^[:space:]].*\\(approved by [^)]*[^) ][^)]*\\)[[:space:]]*\$"
}

# Features with surfaces= in .plumbline (v0.4b) are checked by surface; legacy
# and v0.4a features have no evidence rule (v0.3).
surfaces=$(feature_meta surfaces)
if [[ -n "$surfaces" ]]; then
  # Evidence rows with Result pass and a Location, as "kind<TAB>surface"; kind and
  # result in any case. A row with no Location points at nothing, so it doesn't
  # count. A fail row beats a pass row for the same kind and surface.
  passed=$(md_table "$dir/qa-report.md" Evidence 2>/dev/null \
    | awk -F'\t' '$1 != "" && $3 != "" && tolower($4) == "pass" { print tolower($1) "\t" $2 }')
  failed=$(md_table "$dir/qa-report.md" Evidence 2>/dev/null \
    | awk -F'\t' '$1 != "" && tolower($4) == "fail" { print tolower($1) "\t" $2 }')
  recorded=$(md_table "$dir/qa-report.md" Evidence 2>/dev/null | awk -F'\t' '
    { r = tolower($4); if (r == "pass" && $3 == "") r = "pass without a location"
      print tolower($1) "\t" $2 "\t" r }')
  seen=","
  IFS=, read -r -a snames <<<"$surfaces"
  for s in "${snames[@]}"; do
    s=$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$s")
    [[ -n "$s" && "$seen" != *",$s,"* ]] || continue
    seen="$seen$s,"
    if ! kind=$(surface_kind "$s"); then
      gaps+=("unknown surface \"$s\" in .plumbline surfaces=: a surface is web-ui, mobile-ui, desktop-ui, api, service, cli, library, data, ai or infra, or <kind>-<name>; ask the user to correct it")
      continue
    fi
    # The one evidence kind each surface kind needs: QA checks that the feature
    # works, so each surface has the record of that check.
    case "$kind" in
      web-ui|desktop-ui) need="journeys" ;;
      mobile-ui)  need="flow-tests" ;;
      api)        need="transcripts" ;;
      service)    need="job-tests" ;;
      cli)        need="golden-output" ;;
      library)    need="doc-examples" ;;
      data)       need="sample-run" ;;
      ai)         need="eval-set" ;;
      infra)      need="plan-output" ;;
    esac
    for k in $need; do
      key=$(printf '%s\t%s' "$k" "$s")
      grep -qxF "$key" <<<"$failed" && is_failed=1 || is_failed=0
      (( is_failed )) || { grep -qxF "$key" <<<"$passed" && continue; }
      evidence_waived "$k" "$s" && continue
      got=$(awk -F'\t' -v k="$k" -v s="$s" '$1 == k && $2 == s && $3 != "" { print $3 }' <<<"$recorded" | sort -u | paste -sd, -)
      (( is_failed )) && got=fail
      gaps+=("no passing $k evidence for $s${got:+ (recorded: $got)}: record it in qa-report.md's Evidence table, or ask the user to waive it; the build skill writes the line (qa-report.md)")
    done
  done
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
done < <({ tr -d '\r' < "$dir/signoff.md"; } 2>/dev/null | grep -E '^[[:space:]]*- \[ \]' | grep -viE '(phase|feature) pr|merged|^[[:space:]]*- \[ \][[:space:]]*Design verification')

if (( ${#gaps[@]} == 0 )); then
  echo "Signoff check: no gaps in $rel."
  exit 0
fi
echo "Signoff check: ${#gaps[@]} gap(s) in $rel:"
printf -- '- %s\n' "${gaps[@]}"
exit 1
