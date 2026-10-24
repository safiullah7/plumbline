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
assert "qa-summary: counts one axe result by impact" has "$report" "| rooms-list | 390 | 1 | 1 | 1 | 0 | qa/a11y/rooms-list-390.json |"
assert "qa-summary: counts an array of axe results" has "$report" "| add-room-dialog | 1280 | 0 | 0 | 0 | 1 | qa/a11y/add-room-dialog-1280.json |"
assert "qa-summary: keeps the rest of the report" has "$report" "BUG-01-001"
bash "$G/qa-summary.sh" >/dev/null
assert "qa-summary: rerunning doesn't duplicate rows" test "$(grep -c '| rooms-list | 390 | 1 |' "$P/qa-report.md")" = 1
out=$(bash "$G/signoff-check.sh")
assert "signoff-check: serious accessibility violations named" has "$out" "rooms-list at 390 has 1 critical and 1 serious violation(s)"
echo '{"violations":[{"id":"region","impact":"moderate"}]}' > "$P/qa/a11y/rooms-list-390.json"
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
rm -f "$P"/qa/a11y/*.json && bash "$G/qa-summary.sh" >/dev/null
assert "signoff-check: no accessibility results is a gap" has "$(bash "$G/signoff-check.sh")" "no accessibility results"
add_after() { # file line-regex text: insert text after the first matching line
  awk -v re="$2" -v text="$3" '{ print } !done && $0 ~ re { print text; done = 1 }' "$1" > "$T/edit" && mv "$T/edit" "$1"
}
add_row() { # file section text: add a row right after that section's table separator
  awk -v sec="## $2" -v text="$3" '/^## / { in_sec = ($0 == sec) } { print } in_sec && /^[|] ---/ { print text; in_sec = 0 }' "$1" > "$T/edit" && mv "$T/edit" "$1"
}
add_after "$P/qa-report.md" '^Verdict: PASS$' "Accessibility waived: no browser in CI (approved by product)"
bash "$G/signoff-check.sh" >/dev/null; rc=$?
assert "signoff-check: an explicit waiver clears it" test "$rc" = 0
cp "$T/qa-report.bak" "$P/qa-report.md"

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
