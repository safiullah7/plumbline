#!/usr/bin/env bash
# Self-test for the Plumbline phase scripts (ac-json, status, signoff-check,
# make-briefs). Run from the repo root:
#   bash tests/scripts-selftest.sh
# Builds the eval suite's clinic fixture in a temp repo and checks each script.
set -u
command -v jq >/dev/null 2>&1 || { echo "jq isn't installed or isn't on PATH."; exit 1; }
ROOT="$(cd "$(dirname "${0//\\//}")/.." && pwd)"
G="$ROOT/plugins/plumbline/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo" && cd "$T/repo"
export HOME="$T" CLAUDE_PROJECT_DIR="$T/repo"
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_DATA PLUMBLINE_TEST_GLOBS
source "$ROOT/plugins/plumbline/evals/_fixture/clinic.sh" >/dev/null
set +e   # the fixture sets -e; the checks below expect non-zero exits
ready_plan


pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
assert() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
has() { grep -qF -- "$2" <<<"$1"; }   # text, fixed string

# Before any QA or sign-off docs exist: missing docs are gaps, with no stray errors.
out=$(bash "$G/signoff-check.sh" 2>&1); rc=$?
assert "signoff-check: missing docs are gaps" test "$rc" = 1
assert "signoff-check: names the missing signoff.md" has "$out" "signoff.md is missing"
assert "signoff-check: no stray shell errors" test -z "$(grep -i 'no such file' <<<"$out")"
mv "$P/acceptance-criteria.md" "$T/ac.md"
out=$(bash "$G/status.sh" 2>&1)
assert "status: says when no ACs are written" has "$out" "ACs: none written yet"
assert "status: says when there's no QA verdict" has "$out" "QA verdict: none yet"
mv "$T/ac.md" "$P/acceptance-criteria.md"

# ac-json: one entry per AC row, status from qa-report's Traceability results.
cat > "$P/qa-report.md" <<'EOF'
# Phase 01 QA report

Verdict: PENDING

## Traceability results
| AC ID | Result | Evidence |
| --- | --- | --- |
| AC-01-001 | Pass | e2e/rooms.spec.ts |

## Bugs
| ID | AC ID | Severity | Status | Summary | Evidence |
| --- | --- | --- | --- | --- | --- |
| BUG-01-001 | AC-01-004 | high | OPEN | Other clinic's rooms listed | shots/leak.png |
| BUG-01-002 | AC-01-005 | low | FIXED | Empty state typo | shots/empty.png |
EOF
json=$(bash "$G/ac-json.sh")
assert "ac-json: writes acceptance-criteria.json" test -f "$P/acceptance-criteria.json"
assert "ac-json: one entry per AC" jq -e 'length == 5' "$P/acceptance-criteria.json"
assert "ac-json: status from QA results" jq -e '.[0] == {id: "AC-01-001", useCase: "UC-01-01", priority: "Must", status: "pass"}' "$P/acceptance-criteria.json"
assert "ac-json: untested when QA has no result" jq -e '.[1].status == "untested"' "$P/acceptance-criteria.json"

# status: coverage from AC IDs in test files, bugs, questions, dirty files by owner.
mkdir -p apps/api/rooms/__tests__
printf "test('AC-01-001 adds', () => {});\ntest('AC-01-003 receptionist', () => {});\n" > apps/api/rooms/rooms.test.js
echo "it('AC-01-002 duplicate')" > apps/api/rooms/__tests__/dup.spec.js
echo "AC-01-004 mentioned in a doc, not a test" > apps/api/rooms/NOTES.md
out=$(bash "$G/status.sh")
assert "status: phase and plan status" has "$out" "Phase $P · dev plan: READY"
assert "status: AC coverage from test files" has "$out" "ACs: 5 · with a test: 3 · without: AC-01-004 AC-01-005"
assert "status: open bugs by severity" has "$out" "Open bugs: critical 0 · high 1 · medium 0 · low 0"
assert "status: dirty files by owner" has "$out" "(by owner: eng-api 3 · product 2 · design 2 · qa 2)"
assert "status: at most 40 lines" test "$(wc -l <<<"$out")" -le 40

# signoff-check: every gap named, exit 1; then a clean phase passes.
phase_template signoff.md
cat > "$P/test-plan.md" <<'EOF'
# Phase 01 test plan

## Traceability
| AC ID | Test cases | Type | Status |
| --- | --- | --- | --- |
| AC-01-001 | TC-01-001 | e2e | Pass |
| AC-01-002 | TC-01-002 | api | Pass |
| AC-01-003 | TC-01-003 | api | Pass |
| AC-01-004 | TC-01-004 | api | Fail |
EOF
echo "| 1 | eng-web | design | Grey out inactive rooms? | | OPEN |" >> "$P/questions.md"
out=$(bash "$G/signoff-check.sh"); rc=$?
assert "signoff-check: exits 1 with gaps" test "$rc" = 1
assert "signoff-check: failing AC named" has "$out" "AC-01-004 has no passing test"
assert "signoff-check: missing AC named" has "$out" "AC-01-005 has no passing test"
assert "signoff-check: verdict named" has "$out" "QA verdict is PENDING, not PASS"
assert "signoff-check: open high bug named" has "$out" "open bug BUG-01-001 (high)"
assert "signoff-check: fixed low bug ignored" test -z "$(grep BUG-01-002 <<<"$out")"
assert "signoff-check: open question named" has "$out" "OPEN question #1: Grey out inactive rooms?"
assert "signoff-check: unticked box named" has "$out" "unticked sign-off box: Product verification"
assert "signoff-check: PR and merge boxes ignored" test -z "$(grep -iE 'Phase PR|Merged' <<<"$out")"
assert "signoff-check: missing accessibility results named" has "$out" "no accessibility results for the 2 screen(s)"

# qa-summary: fills the generated Visual comparison and Accessibility sections.
mkdir -p "$P/qa/a11y"
printf 'rooms-list	390	3.1%%	20%%	ok	qa/diff/rooms-list-390.png
' > "$P/qa/visual.tsv"
echo '{"violations":[{"id":"image-alt","impact":"critical"},{"id":"color-contrast","impact":"serious"},{"id":"region","impact":"moderate"}]}' > "$P/qa/a11y/rooms-list-390.json"
echo '[{"violations":[{"id":"label","impact":"minor"}]},{"violations":[]}]' > "$P/qa/a11y/add-room-dialog-1280.json"
bash "$G/qa-summary.sh" >/dev/null
report=$(cat "$P/qa-report.md")
assert "qa-summary: visual row written" has "$report" "| rooms-list | 390 | 3.1% | 20% | ok | qa/diff/rooms-list-390.png |"
assert "qa-summary: counts one axe result by impact" has "$report" "| rooms-list | 390 | 1 | 1 | 1 | 0 | qa/a11y/rooms-list-390.json | axe |"
assert "qa-summary: counts an array of axe results" has "$report" "| add-room-dialog | 1280 | 0 | 0 | 0 | 1 | qa/a11y/add-room-dialog-1280.json | axe |"
assert "qa-summary: keeps the rest of the report" has "$report" "BUG-01-001"
bash "$G/qa-summary.sh" >/dev/null
assert "qa-summary: rerunning doesn't duplicate rows" test "$(grep -c '| rooms-list | 390 | 1 |' "$P/qa-report.md")" = 1
out=$(bash "$G/signoff-check.sh")
assert "signoff-check: serious accessibility violations named" has "$out" "rooms-list at 390 has 1 critical and 1 serious violation(s)"
echo '{"violations":[{"id":"region","impact":"moderate"}]}' > "$P/qa/a11y/rooms-list-390.json"

# qa-summary: the manual accessibility checklist adds Method "checklist" rows.
printf '# screen\twidth\tcheck\tresult\timpact\tevidence\r\nsettings\t390\tfocus-visible\tfail\tcritical\tqa/shots/a.png\r\n\r\nsettings\t390\tlabels\tfail\tminor\tqa/shots/b.png\nsettings\t390\ttargets\tpass\tserious\tqa/shots/c.png\nhome\t390\tlabels\tpass\tserious\tqa/shots/d.png\n' > "$P/qa/a11y-checklist.tsv"
bash "$G/qa-summary.sh" >/dev/null
report=$(cat "$P/qa-report.md")
assert "qa-summary: checklist failures add up by impact" has "$report" "| settings | 390 | 1 | 0 | 0 | 1 | qa/a11y-checklist.tsv | checklist |"
assert "qa-summary: all-pass checklist screen gets zeros" has "$report" "| home | 390 | 0 | 0 | 0 | 0 | qa/a11y-checklist.tsv | checklist |"
assert "qa-summary: axe rows keep Method axe beside checklist rows" has "$report" "| add-room-dialog | 1280 | 0 | 0 | 0 | 1 | qa/a11y/add-room-dialog-1280.json | axe |"
assert "qa-summary: Accessibility header has Method" has "$report" "| Screen | Width | Critical | Serious | Moderate | Minor | Report | Method |"
assert "qa-summary: axe rows come before checklist rows" test "$(grep -n 'add-room-dialog | 1280' "$P/qa-report.md" | cut -d: -f1)" -lt "$(grep -n '| settings | 390' "$P/qa-report.md" | cut -d: -f1)"
bash "$G/qa-summary.sh" >/dev/null
assert "qa-summary: rerunning doesn't duplicate checklist rows" test "$(grep -c '| settings | 390 |' "$P/qa-report.md")" = 1
printf 'settings\t390\tcontrast\tfail\tserious\tqa/shots/e.png\n' >> "$P/qa/a11y-checklist.tsv"
bash "$G/qa-summary.sh" >/dev/null
assert "qa-summary: checklist serious failure is counted" has "$(cat "$P/qa-report.md")" "| settings | 390 | 1 | 1 | 0 | 1 | qa/a11y-checklist.tsv | checklist |"
assert "signoff-check: serious checklist failure named" has "$(bash "$G/signoff-check.sh")" "settings at 390 has 1 critical and 1 serious violation(s)"
printf 'settings\t390\tlabels\tpass\tminor\tqa/shots/b.png\nhome\t390\tlabels\tpass\tserious\tqa/shots/d.png\n' > "$P/qa/a11y-checklist.tsv"
bash "$G/qa-summary.sh" >/dev/null

# Checklist rows: result and impact are compared in lower case, an unknown impact on a
# fail counts as serious, and a header row or an unfilled result is not a row.
printf 'screen\twidth\tcheck\tresult\timpact\tevidence\nhome\t390\tcontrast\tFail\tCritical\tqa/shots/a.png\nhome\t390\tlabels\tFAIL\tmoderate\tqa/shots/b.png\nhome\t390\ttargets\tfail\thigh\tqa/shots/c.png\nhome\t390\tfocus\tfail\t\tqa/shots/d.png\nhome\t390\tzoom\tPass\tserious\tqa/shots/e.png\nhome\t390\ttodo\t\t\tqa/shots/f.png\nhome\t390\tmaybe\tn/a\tcritical\tqa/shots/g.png\n' > "$P/qa/a11y-checklist.tsv"
bash "$G/qa-summary.sh" >/dev/null
report=$(cat "$P/qa-report.md")
assert "qa-summary: Fail/Critical in any case is counted, unknown impacts are serious" has "$report" "| home | 390 | 1 | 2 | 1 | 0 | qa/a11y-checklist.tsv | checklist |"
assert "qa-summary: header row is not a screen" test -z "$(grep -i '^| screen |' <<<"$report" | grep -v 'Screen | Width')"
assert "qa-summary: unfilled and n/a results add nothing" test "$(grep -c '| home | 390 |' "$P/qa-report.md")" = 1
printf 'screen\twidth\tcheck\tresult\timpact\n' > "$P/qa/a11y-checklist.tsv"
bash "$G/qa-summary.sh" >/dev/null
assert "qa-summary: a header-only checklist writes no rows" test -z "$(grep 'checklist |' "$P/qa-report.md")"
printf 'settings\t390\tlabels\tpass\tminor\tqa/shots/b.png\nhome\t390\tlabels\tpass\tserious\tqa/shots/d.png\n' > "$P/qa/a11y-checklist.tsv"
bash "$G/qa-summary.sh" >/dev/null

sed -i 's/| Fail |/| Pass |/' "$P/test-plan.md"
echo "| AC-01-005 | TC-01-005 | e2e | Pass |" >> "$P/test-plan.md"
sed -i 's/^Verdict: PENDING/Verdict: PASS/; s/| high | OPEN |/| high | VERIFIED |/' "$P/qa-report.md"
sed -i 's/| OPEN |$/| ANSWERED |/' "$P/questions.md"
sed -i -E '/Phase PR|Merged/! s/^- \[ \]/- [x]/' "$P/signoff.md"
out=$(bash "$G/signoff-check.sh"); rc=$?
assert "signoff-check: clean phase exits 0" test "$rc" = 0
assert "signoff-check: says no gaps" has "$out" "no gaps"

# A scan that wasn't run blocks signoff unless it's explicitly waived.
cp "$P/qa-report.md" "$T/qa-report.bak"
sed -i 's/^| rooms-list | 390 | 0 | 0 |/| rooms-list | 390 | skipped | skipped |/' "$P/qa-report.md"
assert "signoff-check: non-numeric accessibility counts are a gap" has "$(bash "$G/signoff-check.sh")" "aren't counts"
rm -f "$P"/qa/a11y/*.json "$P/qa/a11y-checklist.tsv" && bash "$G/qa-summary.sh" >/dev/null
assert "signoff-check: no accessibility results is a gap" has "$(bash "$G/signoff-check.sh")" "no accessibility results"
add_after() { # file line-regex text: insert text after the first matching line
  awk -v re="$2" -v text="$3" '{ print } !done && $0 ~ re { print text; done = 1 }' "$1" > "$T/edit" && mv "$T/edit" "$1"
}
add_row() { # file section text: add a row right after that section's table separator
  awk -v sec="## $2" -v text="$3" '/^## / { in_sec = ($0 == sec) } { print } in_sec && /^[|] ---/ { print text; in_sec = 0 }' "$1" > "$T/edit" && mv "$T/edit" "$1"
}
assert "signoff-check: gap message doesn't hand out a waiver line to paste" test -z "$(bash "$G/signoff-check.sh" | grep 'Accessibility waived:')"
assert "signoff-check: gap message says to ask the user" has "$(bash "$G/signoff-check.sh")" "ask the user to waive it"
cp "$P/qa-report.md" "$T/qa-nowaiver.bak"
for w in "Accessibility waived: <reason> (approved by <who>)" \
         "Accessibility waived: no browser in CI (approved by <who>)" \
         "Accessibility waived: <reason> (approved by product)" \
         "Accessibility waived: no browser in CI" \
         "Accessibility waived: no browser in CI (approved by )" \
         "Accessibility waived: no browser in CI (approved by)" \
         "Accessibility waived: no browser in CI (approved by product) and more"; do
  cp "$T/qa-nowaiver.bak" "$P/qa-report.md"
  add_after "$P/qa-report.md" '^Verdict: PASS$' "$w"
  bash "$G/signoff-check.sh" >/dev/null; rc=$?
  assert "signoff-check: not a waiver: $w" test "$rc" = 1
done
cp "$T/qa-nowaiver.bak" "$P/qa-report.md"
add_after "$P/qa-report.md" '^Verdict: PASS$' "Accessibility waived: no browser in CI (approved by product)"
bash "$G/signoff-check.sh" >/dev/null; rc=$?
assert "signoff-check: an explicit waiver clears it" test "$rc" = 0
cp "$T/qa-nowaiver.bak" "$P/qa-report.md"
add_after "$P/qa-report.md" '^Verdict: PASS$' "accessibility waived: no browser in CI (Approved by Dana Smith)  "
bash "$G/signoff-check.sh" >/dev/null; rc=$?
assert "signoff-check: waiver is case-insensitive and may carry a full name" test "$rc" = 0
sed 's/$/\r/' "$P/qa-report.md" > "$T/edit" && mv "$T/edit" "$P/qa-report.md"
bash "$G/signoff-check.sh" >/dev/null; rc=$?
assert "signoff-check: waiver in a CRLF file counts" test "$rc" = 0
cp "$T/qa-nowaiver.bak" "$P/qa-report.md"
sed -i 's/^Verdict: PASS/Verdict: pass/' "$P/qa-report.md"
add_after "$P/qa-report.md" '^Verdict: pass$' "Accessibility waived: no browser in CI (approved by product)"
bash "$G/signoff-check.sh" >/dev/null; rc=$?
assert "signoff-check: a lower-case verdict still passes" test "$rc" = 0
cp "$T/qa-report.bak" "$P/qa-report.md"

# signoff-check: the PR boxes stay unticked, whatever the layout calls them.
cp "$P/signoff.md" "$T/signoff.bak"
printf '%s\n' '- [ ] Feature PR opened: #12' '- [ ] Phase PR opened: #13' >> "$P/signoff.md"
out=$(bash "$G/signoff-check.sh"); rc=$?
assert "signoff-check: unticked Feature PR and Phase PR boxes ignored" test "$rc" = 0
printf '%s\n' '- [ ] Release notes written' >> "$P/signoff.md"
out=$(bash "$G/signoff-check.sh"); rc=$?
assert "signoff-check: other unticked boxes still flagged" test "$rc" = 1
assert "signoff-check: names the unticked box" has "$out" "unticked sign-off box: Release notes written"
assert "signoff-check: PR boxes not named beside it" test -z "$(grep -iE 'PR opened' <<<"$out")"
cp "$T/signoff.bak" "$P/signoff.md"

# signoff-check by surface: .plumbline surfaces= sets the required evidence kinds
# and the accessibility rule; features without it keep the v0.3 rules above.
cp "$P/qa-report.md" "$T/qa-surface.orig"
printf '\n## Evidence\n| Kind | Surface | Location | Result |\n| --- | --- | --- | --- |\n' >> "$P/qa-report.md"
cp "$P/qa-report.md" "$T/qa-surface.bak"
surface_case() { # surfaces kind:surface...: the clean report, .plumbline and passing Evidence rows
  local e
  cp "$T/qa-surface.bak" "$P/qa-report.md"
  printf 'module=clinic\nprofile=full\nsurfaces=%s\nux=yes\n' "$1" > "$P/.plumbline"; shift
  for e in "$@"; do printf '| %s | %s | qa/evidence/%s.txt | pass |\n' "${e%%:*}" "${e#*:}" "${e%%:*}" >> "$P/qa-report.md"; done
}
no_axe_rows() { grep -v '| axe |$' "$P/qa-report.md" > "$T/edit" && mv "$T/edit" "$P/qa-report.md"; }
no_a11y_rows() { grep -vE '\| (axe|checklist) \|$' "$P/qa-report.md" > "$T/edit" && mv "$T/edit" "$P/qa-report.md"; }
signoff() { out=$(bash "$G/signoff-check.sh"); rc=$?; }
api_ev="contract:api authz:api negative:api transcripts:api"

surface_case api $api_ev; no_a11y_rows; signoff
assert "signoff-check: api feature passes with contract, authz, negative and transcripts" test "$rc" = 0
surface_case api contract:api negative:api transcripts:api; signoff
assert "signoff-check: api feature without authz evidence exits 1" test "$rc" = 1
assert "signoff-check: evidence gap names the kind and the surface" has "$out" "no passing authz evidence for api: record it in qa-report.md's Evidence table, or ask the user to waive it; the build skill writes the line"
assert "signoff-check: evidence gap names only the missing kind" test -z "$(grep -E 'contract|negative|transcripts' <<<"$out")"
assert "signoff-check: evidence gap doesn't hand out a waiver line" test -z "$(grep 'Evidence waived:' <<<"$out")"
printf '| authz | api | qa/evidence/authz.txt | not run |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a not-run evidence row is a gap that shows its result" has "$out" "no passing authz evidence for api (recorded: not run)"
# A fail row wins over a pass row for the same kind and surface, in either order.
surface_case api $api_ev; no_a11y_rows
printf '| authz | api | qa/evidence/authz-2.txt | fail |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a pass row plus a fail row for the same kind is a gap" test "$rc" = 1
assert "signoff-check: the fail gap shows what was recorded" has "$out" "no passing authz evidence for api (recorded: fail)"
assert "signoff-check: the fail gap names only that kind" test "$(grep -c 'no passing' <<<"$out")" = 1
surface_case api $api_ev; no_a11y_rows
sed -i 's/^| authz | api |\(.*\)| pass |$/| authz | api |\1| FAIL |/' "$P/qa-report.md"
printf '| authz | api | qa/evidence/authz-2.txt | pass |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a fail row before the pass row is a gap too" has "$out" "no passing authz evidence for api (recorded: fail)"
add_after "$P/qa-report.md" '^Verdict: PASS$' "Evidence waived: authz (api) - the gateway enforces it (approved by Dana)"; signoff
assert "signoff-check: an approved waiver still clears a failed evidence kind" test "$rc" = 0
surface_case api $api_ev; no_a11y_rows
printf '| authz | cli | qa/evidence/authz.txt | fail |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a fail row on another surface doesn't count" test "$rc" = 0
# A pass row with no Location points at nothing, so it doesn't count.
surface_case api $api_ev; no_a11y_rows
sed -i 's/^| authz | api | qa\/evidence\/authz.txt | pass |$/| authz | api |  | pass |/' "$P/qa-report.md"; signoff
assert "signoff-check: a pass row with an empty Location is a gap" has "$out" "no passing authz evidence for api (recorded: pass without a location)"
printf '| authz | api | qa/evidence/authz-2.txt | pass |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a second pass row with a Location closes it" test "$rc" = 0
surface_case api contract:api negative:api transcripts:api
printf '| authz | api | qa/evidence/authz.txt | not run |\n' >> "$P/qa-report.md"
cp "$P/qa-report.md" "$T/qa-noauthz.bak"
for w in "Evidence waived: authz (api) - the gateway enforces it (approved by Dana)" \
         "Evidence waived: authz (api) — the gateway enforces it (approved by Dana Smith)" \
         "evidence waived: authz (api): the gateway enforces it (Approved by product)  "; do
  cp "$T/qa-noauthz.bak" "$P/qa-report.md"
  add_after "$P/qa-report.md" '^Verdict: PASS$' "$w"; signoff
  assert "signoff-check: evidence waiver closes it: $w" test "$rc" = 0
done
for w in "Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)" \
         "Evidence waived: authz (api) - <reason> (approved by Dana)" \
         "Evidence waived: authz (api) - the gateway enforces it (approved by <name>)" \
         "Evidence waived: authz (api) - the gateway enforces it (approved by )" \
         "Evidence waived: authz (api) - the gateway enforces it" \
         "Evidence waived: authz (api) - (approved by Dana)" \
         "Evidence waived: authz (web-ui) - the gateway enforces it (approved by Dana)" \
         "Evidence waived: negative (api) - the gateway enforces it (approved by Dana)" \
         "Accessibility waived: the gateway enforces it (approved by Dana)"; do
  cp "$T/qa-noauthz.bak" "$P/qa-report.md"
  add_after "$P/qa-report.md" '^Verdict: PASS$' "$w"; signoff
  assert "signoff-check: not an authz (api) waiver: $w" test "$rc" = 1
done
surface_case api $api_ev; sed -i 's/^| contract | api |\(.*\)| pass |$/| Contract | api |\1| PASS |/' "$P/qa-report.md"; signoff
assert "signoff-check: evidence kind and result match in any case" test "$rc" = 0
surface_case api $api_ev; sed -i 's/^| add-room-dialog | 1280 | 0 | 0 |/| add-room-dialog | 1280 | 0 | 1 |/' "$P/qa-report.md"; signoff
assert "signoff-check: a serious accessibility count blocks a surface with no UI too" has "$out" "add-room-dialog at 1280 has 0 critical and 1 serious violation(s)"

surface_case mobile-ui screenshots:mobile-ui flow-tests:mobile-ui checklist:mobile-ui; no_axe_rows; signoff
assert "signoff-check: mobile feature passes with checklist rows and no axe" test "$rc" = 0
surface_case mobile-ui; signoff
assert "signoff-check: mobile feature needs screenshots" has "$out" "no passing screenshots evidence for mobile-ui"
assert "signoff-check: mobile feature needs flow-tests" has "$out" "no passing flow-tests evidence for mobile-ui"
assert "signoff-check: mobile feature needs checklist evidence" has "$out" "no passing checklist evidence for mobile-ui"
assert "signoff-check: mobile feature doesn't need axe evidence" test -z "$(grep 'axe' <<<"$out")"
surface_case mobile-ui screenshots:mobile-ui flow-tests:mobile-ui checklist:mobile-ui; no_a11y_rows; signoff
assert "signoff-check: mobile feature without checklist rows names it" has "$out" "no checklist accessibility results for mobile-ui"
surface_case mobile-ui screenshots:mobile-ui flow-tests:mobile-ui checklist:mobile-ui
grep -v '| checklist |$' "$P/qa-report.md" > "$T/edit" && mv "$T/edit" "$P/qa-report.md"; signoff
assert "signoff-check: axe rows don't stand in for a mobile checklist" has "$out" "no checklist accessibility results for mobile-ui"
surface_case desktop-ui screenshots:desktop-ui checklist:desktop-ui; no_axe_rows; signoff
assert "signoff-check: desktop feature passes with screenshots, checklist and checklist rows" test "$rc" = 0

web_ev="screenshots:web-ui axe:web-ui journeys:web-ui"
surface_case web-ui $web_ev; signoff
assert "signoff-check: web feature passes with its evidence and axe rows" test "$rc" = 0
surface_case web-ui $web_ev; no_axe_rows; signoff
assert "signoff-check: web feature with checklist rows but no axe rows blocks" test "$rc" = 1
assert "signoff-check: names the missing axe results" has "$out" "no axe accessibility results for web-ui: run the scan, or ask the user to waive it"
surface_case web-ui $web_ev; no_a11y_rows; signoff
assert "signoff-check: web feature with neither axe rows nor a waiver blocks" has "$out" "no axe accessibility results for web-ui"
add_after "$P/qa-report.md" '^Verdict: PASS$' "Accessibility waived: no browser in CI (approved by product)"; signoff
assert "signoff-check: an accessibility waiver clears a web feature's missing rows" test "$rc" = 0
surface_case web-ui screenshots:web-ui journeys:web-ui; signoff
assert "signoff-check: web feature needs axe evidence too" has "$out" "no passing axe evidence for web-ui"
surface_case web-ui screenshots:web-ui journeys:web-ui; no_a11y_rows
add_after "$P/qa-report.md" '^Verdict: PASS$' "Accessibility waived: no browser in CI (approved by product)"; signoff
assert "signoff-check: the accessibility waiver also covers the axe evidence (asked once)" test "$rc" = 0
surface_case mobile-ui screenshots:mobile-ui flow-tests:mobile-ui; no_a11y_rows
add_after "$P/qa-report.md" '^Verdict: PASS$' "Accessibility waived: no device in CI (approved by product)"; signoff
assert "signoff-check: the accessibility waiver also covers the checklist evidence" test "$rc" = 0
surface_case web-ui journeys:web-ui; no_a11y_rows
add_after "$P/qa-report.md" '^Verdict: PASS$' "Accessibility waived: no browser in CI (approved by product)"; signoff
assert "signoff-check: the accessibility waiver doesn't cover screenshots" has "$out" "no passing screenshots evidence for web-ui"

surface_case cli; no_a11y_rows; signoff
assert "signoff-check: cli feature needs golden-output" has "$out" "no passing golden-output evidence for cli"
assert "signoff-check: cli feature is exempt from accessibility" test -z "$(grep -i 'accessibility' <<<"$out")"
surface_case cli golden-output:cli; no_a11y_rows; signoff
assert "signoff-check: cli feature passes with golden-output" test "$rc" = 0

surface_case "api,web-ui" $api_ev; signoff
assert "signoff-check: two surfaces need the union (web-ui screenshots)" has "$out" "no passing screenshots evidence for web-ui"
assert "signoff-check: two surfaces need the union (web-ui journeys)" has "$out" "no passing journeys evidence for web-ui"
assert "signoff-check: two surfaces don't flag the surface that's covered" test -z "$(grep 'for api' <<<"$out")"
surface_case "web-ui,api" $web_ev; signoff
assert "signoff-check: two surfaces need the union (api authz)" has "$out" "no passing authz evidence for api"
surface_case "api,web-ui" $api_ev $web_ev; signoff
assert "signoff-check: two surfaces pass with both sets" test "$rc" = 0
surface_case "api,web-ui" $api_ev $web_ev; no_a11y_rows; signoff
assert "signoff-check: two surfaces with a UI need accessibility rows" has "$out" "no axe accessibility results for web-ui"
surface_case "ai" eval-set:ai injection:ai; no_a11y_rows; signoff
assert "signoff-check: ai feature is exempt from accessibility" test "$rc" = 0
surface_case "ai,web-ui" eval-set:ai injection:ai $web_ev; no_a11y_rows; signoff
assert "signoff-check: ai feature with a UI surface needs accessibility rows" has "$out" "no axe accessibility results for web-ui"

surface_case web-ui-shop screenshots:web-ui-shop axe:web-ui-shop journeys:web-ui-shop; signoff
assert "signoff-check: web-ui-shop is checked as web-ui" test "$rc" = 0
surface_case web-ui-shop $web_ev; signoff
assert "signoff-check: evidence rows name the surface as written" has "$out" "no passing screenshots evidence for web-ui-shop"
surface_case web-ui-shop screenshots:web-ui-shop axe:web-ui-shop journeys:web-ui-shop; no_axe_rows; signoff
assert "signoff-check: web-ui-shop needs axe rows" has "$out" "no axe accessibility results for web-ui-shop"
surface_case foo; signoff
assert "signoff-check: unknown surface is a gap" test "$rc" = 1
assert "signoff-check: names the unknown surface" has "$out" 'unknown surface "foo" in .plumbline'

# Without surfaces= (legacy, and v0.4a's .plumbline): no evidence rule, v0.3 accessibility.
rm -f "$P/.plumbline"; cp "$T/qa-surface.bak" "$P/qa-report.md"; signoff
assert "signoff-check: legacy feature needs no Evidence rows" test "$rc" = 0
no_a11y_rows; signoff
assert "signoff-check: legacy feature keeps the ux.md screens rule" has "$out" "no accessibility results for the 2 screen(s) in ux.md"
printf 'module=clinic\nprofile=standard\nux=yes\n' > "$P/.plumbline"; cp "$T/qa-surface.bak" "$P/qa-report.md"; signoff
assert "signoff-check: v0.4a feature needs no Evidence rows" test "$rc" = 0
no_a11y_rows; signoff
assert "signoff-check: v0.4a feature keeps the ux.md screens rule" has "$out" "no accessibility results for the 2 screen(s) in ux.md"
assert "signoff-check: v0.4a feature has no evidence gaps" test -z "$(grep 'evidence for' <<<"$out")"
rm -f "$P/.plumbline"; cp "$T/qa-surface.orig" "$P/qa-report.md"

# phase-evidence: what shipped with problems, what was left out, unmet metrics.
add_row "$P/qa-report.md" Bugs "| BUG-01-003 | AC-01-005 | medium | WONTFIX | Empty state icon misaligned | shots/empty.png |"
add_row "$P/signoff.md" "Design findings" "| 1 | Rooms list | Badge colour too close to brand blue | medium | OPEN | shots/badge.png |"
add_row "$P/signoff.md" "Success metrics results" "| Admin sets up 10 rooms | under 3 min | 4.5 min | no |"
out=$(bash "$G/phase-evidence.sh")
assert "phase-evidence: unmet success metric" has "$out" "Admin sets up 10 rooms: target under 3 min, result 4.5 min (met: no)"
assert "phase-evidence: WONTFIX bug" has "$out" "BUG-01-003 (medium, wontfix): Empty state icon misaligned"
assert "phase-evidence: open medium design finding" has "$out" "design #1 (medium, open): Badge colour too close to brand blue"
assert "phase-evidence: Non-Goals (Out of scope in older specs)" has "$out" "Booking appointments into rooms (phase 03)"
assert "phase-evidence: leaves out verified high bugs" test -z "$(grep BUG-01-001 <<<"$out")"
assert "phase-evidence: at most 80 lines" test "$(wc -l <<<"$out")" -le 80

# phase-evidence on the new layout (<module>/<nn>-<slug>/) and on a mixed module
# (legacy phases/phase-01 beside 02-x), listed in number order.
printf '%s\n' "$(head -n1 .claude/current-phase)" > "$T/current-phase.bak"
bug_report() { # file id severity: a qa-report.md with one open bug
  printf '# QA report\n\nVerdict: PASS\n\n## Bugs\n| ID | AC ID | Severity | Status | Summary | Evidence |\n| --- | --- | --- | --- | --- | --- |\n| %s | AC-01-001 | %s | OPEN | Problem in %s | - |\n' "$2" "$3" "$2" > "$1"
}
mkdir -p docs/product/shop/04-a docs/product/shop/05-b
bug_report docs/product/shop/04-a/qa-report.md BUG-04-001 low
bug_report docs/product/shop/05-b/qa-report.md BUG-05-001 medium
echo "docs/product/shop/05-b" > .claude/current-phase
out=$(bash "$G/phase-evidence.sh")
assert "phase-evidence: new layout names the module" has "$out" "Evidence for the next feature in docs/product/shop."
assert "phase-evidence: new layout points to vision.md and decisions.md" has "$out" "docs/product/shop/vision.md and docs/product/shop/decisions.md"
assert "phase-evidence: new layout lists the first feature" has "$out" "BUG-04-001 (low, open): Problem in BUG-04-001"
assert "phase-evidence: new layout lists the second feature" has "$out" "BUG-05-001 (medium, open): Problem in BUG-05-001"
assert "phase-evidence: new layout in number order" test "$(grep '^## ' <<<"$out" | tr '\n' ' ')" = "## 04-a ## 05-b "
assert "phase-evidence: new layout at most 80 lines" test "$(wc -l <<<"$out")" -le 80
mkdir -p docs/product/old/phases/phase-01 docs/product/old/02-x
bug_report docs/product/old/phases/phase-01/qa-report.md BUG-01-009 low
bug_report docs/product/old/02-x/qa-report.md BUG-02-001 low
echo "docs/product/old/02-x" > .claude/current-phase
out=$(bash "$G/phase-evidence.sh")
assert "phase-evidence: mixed module lists the legacy phase" has "$out" "BUG-01-009 (low, open)"
assert "phase-evidence: mixed module lists the new feature" has "$out" "BUG-02-001 (low, open)"
assert "phase-evidence: mixed module in number order" test "$(grep '^## ' <<<"$out" | tr '\n' ' ')" = "## phase-01 ## 02-x "
assert "phase-evidence: mixed module at most 80 lines" test "$(wc -l <<<"$out")" -le 80
mkdir -p docs/product/old/phases/hotfix docs/product/old/phases/archive
bug_report docs/product/old/phases/hotfix/qa-report.md BUG-HF-001 low
bug_report docs/product/old/phases/archive/qa-report.md BUG-AR-001 low
out=$(bash "$G/phase-evidence.sh")
assert "phase-evidence: non-numeric legacy folder is listed" has "$out" "BUG-HF-001 (low, open)"
assert "phase-evidence: numbered features first, then non-numeric folders by name" test "$(grep '^## ' <<<"$out" | tr '\n' ' ')" = "## phase-01 ## 02-x ## archive ## hotfix "
echo "docs/product/old/phases/phase-01" > .claude/current-phase
assert "phase-evidence: same module from a legacy feature" has "$(bash "$G/phase-evidence.sh")" "BUG-02-001 (low, open)"
cp "$T/current-phase.bak" .claude/current-phase
rm -rf docs/product/shop docs/product/old

# status: test files named the Go, Python, Dart, Swift and C# way count too.
mkdir -p apps/api/svc
echo "func TestAC_01_004(t *testing.T) {} // AC-01-004" > apps/api/svc/rooms_test.go
echo "def test_room(): pass  # AC-01-005" > apps/api/svc/test_rooms.py
out=$(bash "$G/status.sh")
assert "status: AC IDs in _test.go and test_*.py files count as covered" has "$out" "ACs: 5 · every one has a test"
rm -rf apps/api/svc

# make-briefs: one brief per engineer, holding only its own ACs.
out=$(bash "$G/make-briefs.sh")
api="$P/briefs/eng-api.md" web="$P/briefs/eng-web.md"
assert "make-briefs: one brief per engineer" test -f "$api" -a -f "$web"
assert "make-briefs: brief lists its globs" grep -qF 'apps/api/**' "$api"
assert "make-briefs: brief holds its own AC rows" grep -q '^| AC-01-002 |' "$api"
assert "make-briefs: brief leaves out other workstreams' ACs" test -z "$(grep '^| AC-01-005 |' "$api")"
assert "make-briefs: web brief holds AC-01-005" grep -q '^| AC-01-005 |' "$web"
assert "make-briefs: brief links the full docs" grep -q "^$P/spec.md" "$api"
assert "make-briefs: brief carries the spec's business rules" grep -qF "Room names are unique within a clinic" "$api"
assert "make-briefs: brief carries data and permissions" grep -qF "Only clinic admins can add" "$api"

# Image comparison and capture (Node). PLUMBLINE_BROWSER_TEST=1 adds a real browser run.
if command -v node >/dev/null 2>&1; then
  while IFS= read -r line; do
    case "$line" in "ok    "*) ok "${line#ok    }" ;; "FAIL  "*) fail "${line#FAIL  }" ;; esac
  done < <(node "$ROOT/tests/visual-selftest.mjs" 2>&1 || echo "FAIL  visual-selftest.mjs crashed")
else
  echo "skip  visual-diff and capture tests (Node isn't installed)"
fi

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
