#!/usr/bin/env bash
# The active phase at a glance: plan status, AC test coverage, open bugs, open
# and escalated questions, and uncommitted files per owner. Read-only. An AC
# counts as covered when its ID appears in a test file (PLUMBLINE_TEST_GLOBS).
source "$(dirname "${0//\\//}")/lib.sh"
dir=$(phase_dir) || { echo "No active phase: .claude/current-phase is missing."; exit 1; }
cd "$PROJECT_DIR" || exit 1
TEST_GLOBS="${PLUMBLINE_TEST_GLOBS:-*.test.* *.spec.* */e2e/* */tests/* */test/* e2e/* tests/* test/*}"
count() { grep -c . <<<"$1"; }

echo "Phase $(phase_rel) · dev plan: $(plan_status || echo none)"

ids=$(md_table "$dir/acceptance-criteria.md" 2>/dev/null | awk -F'\t' '$1 ~ /^AC-[0-9]+-[0-9]+$/ { print $1 }' | sort -u)
tested=$( { git ls-files; git ls-files -o --exclude-standard; } 2>/dev/null | tr -d '\r' \
  | while IFS= read -r f; do matches_globs "$f" "$TEST_GLOBS" && printf '%s\0' "$f"; done \
  | xargs -0 -r grep -ohE 'AC-[0-9]+-[0-9]+' 2>/dev/null | sort -u)
missing=$(comm -23 <(printf '%s\n' "$ids") <(printf '%s\n' "$tested") | grep .)
if [[ -z "$ids" ]]; then
  echo "ACs: none written yet"
elif [[ -z "$missing" ]]; then
  echo "ACs: $(count "$ids") · every one has a test"
else
  echo "ACs: $(count "$ids") · with a test: $(( $(count "$ids") - $(count "$missing") )) · without: $(echo $missing)"
fi

md_table "$dir/qa-report.md" Bugs 2>/dev/null | awk -F'\t' '
  $1 != "" && toupper($4) !~ /^(FIXED|VERIFIED|WONTFIX|CLOSED)$/ { c[tolower($3)]++ }
  END { printf "Open bugs: critical %d · high %d · medium %d · low %d\n", c["critical"], c["high"], c["medium"], c["low"] }'
verdict=$(grep -m1 -iE '^Verdict:' "$dir/qa-report.md" 2>/dev/null | tr -d '\r' | sed -E 's/^[Vv]erdict:[[:space:]]*//')
echo "QA verdict: ${verdict:-none yet}"

q=$(md_table "$dir/questions.md" 2>/dev/null)
esc=$(awk -F'\t' 'toupper($6) == "ESCALATED"' <<<"$q")
echo "Questions: $(awk -F'\t' 'toupper($6) == "OPEN"' <<<"$q" | grep -c .) open · $(count "$esc") escalated"
[[ -n "$esc" ]] && awk -F'\t' '{ printf "  ESCALATED #%s: %s\n", $1, substr($4, 1, 120) }' <<<"$esc" | head -n 5

dirty=$(dirty_files)
if [[ -z "$dirty" ]]; then
  echo "Uncommitted files: none"
else
  line=""
  while IFS=$'\t' read -r name globs _; do
    [[ -n "$name" ]] || continue
    n=0
    while IFS= read -r f; do
      shared_path "$f" && continue
      matches_globs "$f" "$globs" && n=$((n + 1))
    done <<<"$dirty"
    (( n > 0 )) && line+="${line:+ · }$name $n"
  done < <(md_table "$dir/dev-plan.md" Ownership 2>/dev/null)
  echo "Uncommitted files: $(count "$dirty") total${line:+ (by owner: $line)}"
fi
