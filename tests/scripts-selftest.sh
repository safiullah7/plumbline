#!/usr/bin/env bash
# Self-test for the Plumbline phase scripts (status, signoff-check,
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
export PLUMBLINE_REUSE=0   # no run here reuses a recorded pass
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

# A QA report with open bugs, for the status checks below.
cat > "$P/qa-report.md" <<'EOF'
# Phase 01 QA report

Verdict: PENDING

## Bugs
| ID | AC ID | Severity | Status | Summary | Evidence |
| --- | --- | --- | --- | --- | --- |
| BUG-01-001 | AC-01-004 | high | OPEN | Other clinic's rooms listed | shots/leak.png |
| BUG-01-002 | AC-01-005 | low | FIXED | Empty state typo | shots/empty.png |
EOF

# status: coverage from AC IDs in test files, bugs, questions, dirty files by owner.
mkdir -p apps/api/rooms/__tests__
printf "test('AC-01-001 adds', () => {});\ntest('AC-01-003 receptionist', () => {});\n" > apps/api/rooms/rooms.test.js
echo "it('AC-01-002 duplicate')" > apps/api/rooms/__tests__/dup.spec.js
echo "AC-01-004 mentioned in a doc, not a test" > apps/api/rooms/NOTES.md
out=$(bash "$G/status.sh")
assert "status: phase and plan status" has "$out" "Phase $P · dev plan: READY"
assert "status: AC coverage from test files" has "$out" "ACs: 5 · with a test: 3 · without: AC-01-004 AC-01-005"
assert "status: open bugs by severity" has "$out" "Open bugs: critical 0 · high 1 · medium 0 · low 0"
assert "status: dirty files by owner" has "$out" "(by owner: eng-api 3 · product 2 · qa 2)"
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

sed -i 's/| Fail |/| Pass |/' "$P/test-plan.md"
echo "| AC-01-005 | TC-01-005 | e2e | Pass |" >> "$P/test-plan.md"
sed -i 's/^Verdict: PENDING/Verdict: PASS/; s/| high | OPEN |/| high | VERIFIED |/' "$P/qa-report.md"
sed -i 's/| OPEN |$/| ANSWERED |/' "$P/questions.md"
sed -i -E '/Phase PR|Merged/! s/^- \[ \]/- [x]/' "$P/signoff.md"
out=$(bash "$G/signoff-check.sh"); rc=$?
assert "signoff-check: clean phase exits 0" test "$rc" = 0
assert "signoff-check: says no gaps" has "$out" "no gaps"

add_after() { # file line-regex text: insert text after the first matching line
  awk -v re="$2" -v text="$3" '{ print } !done && $0 ~ re { print text; done = 1 }' "$1" > "$T/edit" && mv "$T/edit" "$1"
}
add_row() { # file section text: add a row right after that section's table separator
  awk -v sec="## $2" -v text="$3" '/^## / { in_sec = ($0 == sec) } { print } in_sec && /^[|] ---/ { print text; in_sec = 0 }' "$1" > "$T/edit" && mv "$T/edit" "$1"
}
signoff() { out=$(bash "$G/signoff-check.sh"); rc=$?; }

# No accessibility rule any more: the check never looks at ux.md screens or at an
# Accessibility table, whatever it holds.
assert "signoff-check: no accessibility wording in a clean report" test -z "$(grep -i 'accessib' <<<"$out")"
cp "$P/qa-report.md" "$T/qa-report.bak"
printf '\n## Accessibility\n| Screen | Width | Critical | Serious | Moderate | Minor | Report | Method |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n| rooms-list | 390 | skipped | skipped | 0 | 0 | - | axe |\n| home | 390 | 2 | 3 | 0 | 0 | - | axe |\n' >> "$P/qa-report.md"
signoff
assert "signoff-check: an old Accessibility table is ignored" test "$rc" = 0
cp "$T/qa-report.bak" "$P/qa-report.md"
sed -i 's/^Verdict: PASS/Verdict: pass/' "$P/qa-report.md"; signoff
assert "signoff-check: a lower-case verdict still passes" test "$rc" = 0
cp "$T/qa-report.bak" "$P/qa-report.md"

# An unticked "Design verification" box (old features) is ignored; other boxes still count.
cp "$P/signoff.md" "$T/signoff.bak"
printf '%s\n' '- [ ] Design verification: screens match the prototypes' >> "$P/signoff.md"; signoff
assert "signoff-check: an unticked Design verification box is ignored" test "$rc" = 0
assert "signoff-check: ...and not named" test -z "$(grep -i 'design verification' <<<"$out")"
printf '%s\n' '  - [ ]   Design verification' >> "$P/signoff.md"; signoff
assert "signoff-check: ...also indented, with extra spaces" test "$rc" = 0
printf '%s\n' '- [ ] Product design review' >> "$P/signoff.md"; signoff
assert "signoff-check: a box that merely mentions design is still flagged" has "$out" "unticked sign-off box: Product design review"
cp "$T/signoff.bak" "$P/signoff.md"

# signoff-check: the PR boxes stay unticked, whatever the layout calls them.
printf '%s\n' '- [ ] Feature PR opened: #12' '- [ ] Phase PR opened: #13' >> "$P/signoff.md"
out=$(bash "$G/signoff-check.sh"); rc=$?
assert "signoff-check: unticked Feature PR and Phase PR boxes ignored" test "$rc" = 0
printf '%s\n' '- [ ] Release notes written' >> "$P/signoff.md"
out=$(bash "$G/signoff-check.sh"); rc=$?
assert "signoff-check: other unticked boxes still flagged" test "$rc" = 1
assert "signoff-check: names the unticked box" has "$out" "unticked sign-off box: Release notes written"
assert "signoff-check: PR boxes not named beside it" test -z "$(grep -iE 'PR opened' <<<"$out")"
cp "$T/signoff.bak" "$P/signoff.md"

# signoff-check by surface: .plumbline surfaces= sets the one required evidence kind
# per surface; features without it have no evidence rule.
cp "$P/qa-report.md" "$T/qa-surface.orig"
printf '\n## Evidence\n| Kind | Surface | Location | Result |\n| --- | --- | --- | --- |\n' >> "$P/qa-report.md"
cp "$P/qa-report.md" "$T/qa-surface.bak"
surface_case() { # surfaces kind:surface...: the clean report, .plumbline and passing Evidence rows
  local e
  cp "$T/qa-surface.bak" "$P/qa-report.md"
  printf 'module=clinic\nprofile=full\nsurfaces=%s\nux=yes\n' "$1" > "$P/.plumbline"; shift
  for e in "$@"; do printf '| %s | %s | qa/evidence/%s.txt | pass |\n' "${e%%:*}" "${e#*:}" "${e%%:*}" >> "$P/qa-report.md"; done
}

# api: transcripts.
surface_case api transcripts:api; signoff
assert "signoff-check: api feature passes with a transcripts row" test "$rc" = 0
surface_case api; signoff
assert "signoff-check: api feature without transcripts exits 1" test "$rc" = 1
assert "signoff-check: evidence gap names the kind and the surface" has "$out" "no passing transcripts evidence for api: record it in qa-report.md's Evidence table, or ask the user to waive it; the build skill writes the line"
assert "signoff-check: evidence gap is the only gap" test "$(grep -c '^- ' <<<"$out")" = 1
assert "signoff-check: evidence gap doesn't hand out a waiver line" test -z "$(grep 'Evidence waived:' <<<"$out")"
surface_case api contract:api authz:api negative:api; signoff
assert "signoff-check: the deeper api kinds don't stand in for transcripts" has "$out" "no passing transcripts evidence for api"
surface_case api transcripts:api contract:api authz:api negative:api api-diff:api; signoff
assert "signoff-check: extra evidence kinds are harmless" test "$rc" = 0
surface_case api; printf '| transcripts | api | qa/evidence/transcripts.txt | not run |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a not-run evidence row is a gap that shows its result" has "$out" "no passing transcripts evidence for api (recorded: not run)"
# A fail row wins over a pass row for the same kind and surface, in either order.
surface_case api transcripts:api
printf '| transcripts | api | qa/evidence/transcripts-2.txt | fail |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a pass row plus a fail row for the same kind is a gap" test "$rc" = 1
assert "signoff-check: the fail gap shows what was recorded" has "$out" "no passing transcripts evidence for api (recorded: fail)"
assert "signoff-check: the fail gap names only that kind" test "$(grep -c 'no passing' <<<"$out")" = 1
surface_case api transcripts:api
sed -i 's/^| transcripts | api |\(.*\)| pass |$/| transcripts | api |\1| FAIL |/' "$P/qa-report.md"
printf '| transcripts | api | qa/evidence/transcripts-2.txt | pass |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a fail row before the pass row is a gap too" has "$out" "no passing transcripts evidence for api (recorded: fail)"
add_after "$P/qa-report.md" '^Verdict: PASS$' "Evidence waived: transcripts (api) - the gateway is tested elsewhere (approved by Dana)"; signoff
assert "signoff-check: an approved waiver still clears a failed evidence kind" test "$rc" = 0
surface_case api transcripts:api
printf '| transcripts | cli | qa/evidence/transcripts.txt | fail |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a fail row on another surface doesn't count" test "$rc" = 0
# A pass row with no Location points at nothing, so it doesn't count.
surface_case api
printf '| transcripts | api |  | pass |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a pass row with an empty Location is a gap" has "$out" "no passing transcripts evidence for api (recorded: pass without a location)"
printf '| transcripts | api | qa/evidence/transcripts-2.txt | pass |\n' >> "$P/qa-report.md"; signoff
assert "signoff-check: a second pass row with a Location closes it" test "$rc" = 0
# Waivers: one per kind and surface, filled in, approved by a name.
surface_case api
printf '| transcripts | api | qa/evidence/transcripts.txt | not run |\n' >> "$P/qa-report.md"
cp "$P/qa-report.md" "$T/qa-notranscripts.bak"
for w in "Evidence waived: transcripts (api) - no test server in CI (approved by Dana)" \
         "Evidence waived: transcripts (api) — no test server in CI (approved by Dana Smith)" \
         "evidence waived: transcripts (api): no test server in CI (Approved by product)  "; do
  cp "$T/qa-notranscripts.bak" "$P/qa-report.md"
  add_after "$P/qa-report.md" '^Verdict: PASS$' "$w"; signoff
  assert "signoff-check: evidence waiver closes it: $w" test "$rc" = 0
done
cp "$T/qa-notranscripts.bak" "$P/qa-report.md"
add_after "$P/qa-report.md" '^Verdict: PASS$' "Evidence waived: transcripts (api) - no test server in CI (approved by Dana)"
sed 's/$/\r/' "$P/qa-report.md" > "$T/edit" && mv "$T/edit" "$P/qa-report.md"; signoff
assert "signoff-check: a waiver in a CRLF file counts" test "$rc" = 0
for w in "Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)" \
         "Evidence waived: transcripts (api) - <reason> (approved by Dana)" \
         "Evidence waived: transcripts (api) - no test server in CI (approved by <name>)" \
         "Evidence waived: transcripts (api) - no test server in CI (approved by )" \
         "Evidence waived: transcripts (api) - no test server in CI" \
         "Evidence waived: transcripts (api) - (approved by Dana)" \
         "Evidence waived: transcripts (web-ui) - no test server in CI (approved by Dana)" \
         "Evidence waived: journeys (api) - no test server in CI (approved by Dana)" \
         "Accessibility waived: no test server in CI (approved by Dana)"; do
  cp "$T/qa-notranscripts.bak" "$P/qa-report.md"
  add_after "$P/qa-report.md" '^Verdict: PASS$' "$w"; signoff
  assert "signoff-check: not a transcripts (api) waiver: $w" test "$rc" = 1
done
surface_case api transcripts:api; sed -i 's/^| transcripts | api |\(.*\)| pass |$/| Transcripts | api |\1| PASS |/' "$P/qa-report.md"; signoff
assert "signoff-check: evidence kind and result match in any case" test "$rc" = 0

# web-ui and desktop-ui: journeys. No screenshots, axe or checklist evidence, no
# accessibility rows.
surface_case web-ui journeys:web-ui; signoff
assert "signoff-check: web feature passes with a journeys row" test "$rc" = 0
assert "signoff-check: web feature needs no accessibility rows" test -z "$(grep -i 'accessib' <<<"$out")"
surface_case web-ui; signoff
assert "signoff-check: web feature needs journeys" has "$out" "no passing journeys evidence for web-ui"
assert "signoff-check: web feature doesn't need screenshots or axe" test -z "$(grep -E 'screenshots|axe' <<<"$out")"
surface_case web-ui screenshots:web-ui axe:web-ui; signoff
assert "signoff-check: screenshots and axe rows don't stand in for journeys" has "$out" "no passing journeys evidence for web-ui"
surface_case desktop-ui journeys:desktop-ui; signoff
assert "signoff-check: desktop feature passes with a journeys row" test "$rc" = 0
surface_case desktop-ui; signoff
assert "signoff-check: desktop feature needs journeys" has "$out" "no passing journeys evidence for desktop-ui"
assert "signoff-check: desktop feature doesn't need screenshots or a checklist" test -z "$(grep -E 'screenshots|checklist' <<<"$out")"

# mobile-ui: flow-tests.
surface_case mobile-ui flow-tests:mobile-ui; signoff
assert "signoff-check: mobile feature passes with a flow-tests row" test "$rc" = 0
surface_case mobile-ui; signoff
assert "signoff-check: mobile feature needs flow-tests" has "$out" "no passing flow-tests evidence for mobile-ui"
assert "signoff-check: mobile feature doesn't need screenshots, a checklist or axe" test -z "$(grep -E 'screenshots|checklist|axe' <<<"$out")"

# The other surface kinds: one kind each, nothing else required.
kind_case() { # surface kind
  surface_case "$1"; signoff
  assert "signoff-check: $1 feature needs $2" has "$out" "no passing $2 evidence for $1"
  assert "signoff-check: $1 feature has just that one gap" test "$(grep -c '^- ' <<<"$out")" = 1
  surface_case "$1" "$2:$1"; signoff
  assert "signoff-check: $1 feature passes with $2" test "$rc" = 0
}
kind_case service job-tests
kind_case cli golden-output
kind_case library doc-examples
kind_case data sample-run
kind_case ai eval-set
kind_case infra plan-output

# Several surfaces need the union of their kinds.
surface_case "api,web-ui" transcripts:api; signoff
assert "signoff-check: two surfaces need the union (web-ui journeys)" has "$out" "no passing journeys evidence for web-ui"
assert "signoff-check: two surfaces don't flag the surface that's covered" test -z "$(grep 'for api' <<<"$out")"
surface_case "web-ui,api" journeys:web-ui; signoff
assert "signoff-check: two surfaces need the union (api transcripts)" has "$out" "no passing transcripts evidence for api"
surface_case "api,web-ui" transcripts:api journeys:web-ui; signoff
assert "signoff-check: two surfaces pass with both rows" test "$rc" = 0
surface_case "api,web-ui,api"; signoff
assert "signoff-check: a surface listed twice is checked once" test "$(grep -c 'transcripts evidence for api' <<<"$out")" = 1
surface_case "api, web-ui" transcripts:api journeys:web-ui; signoff
assert "signoff-check: spaces around a surface name are trimmed" test "$rc" = 0
# An evidence waiver is per surface: it covers one of the two, not both.
surface_case "api,web-ui"
add_after "$P/qa-report.md" '^Verdict: PASS$' "Evidence waived: transcripts (api) - no test server in CI (approved by Dana)"; signoff
assert "signoff-check: a waiver for one surface leaves the other's gap" has "$out" "no passing journeys evidence for web-ui"
assert "signoff-check: ...and clears its own" test -z "$(grep 'for api' <<<"$out")"

# A <kind>-<name> surface is checked as its kind, and its rows name it as written.
surface_case web-ui-shop journeys:web-ui-shop; signoff
assert "signoff-check: web-ui-shop is checked as web-ui" test "$rc" = 0
surface_case web-ui-shop journeys:web-ui; signoff
assert "signoff-check: evidence rows name the surface as written" has "$out" "no passing journeys evidence for web-ui-shop"
surface_case foo; signoff
assert "signoff-check: unknown surface is a gap" test "$rc" = 1
assert "signoff-check: names the unknown surface" has "$out" 'unknown surface "foo" in .plumbline'

# Without surfaces= (legacy, and v0.4a's .plumbline): no evidence rule, no accessibility rule.
rm -f "$P/.plumbline"; cp "$T/qa-surface.bak" "$P/qa-report.md"; signoff
assert "signoff-check: legacy feature needs no Evidence rows" test "$rc" = 0
assert "signoff-check: legacy feature has no accessibility rule (ux.md has screens)" test -z "$(grep -i 'accessib' <<<"$out")"
printf 'module=clinic\nprofile=standard\nux=yes\n' > "$P/.plumbline"; cp "$T/qa-surface.bak" "$P/qa-report.md"; signoff
assert "signoff-check: v0.4a feature needs no Evidence rows" test "$rc" = 0
assert "signoff-check: v0.4a feature has no evidence or accessibility gaps" test -z "$(grep -iE 'evidence for|accessib' <<<"$out")"
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
assert "phase-evidence: no security section without security findings" test -z "$(grep -i 'security' <<<"$out")"

# phase-evidence and status (v0.6.2): security findings left deferred (medium, low) or
# accepted (critical, high), from every feature of the repo, with folder and number.
printf 'module=clinic\nnumber=01\nprofile=full\nux=yes\nsecurity=attacks\n' > "$P/.plumbline"
sec_file() { # folder, findings rows (one per line)
  printf '# Feature security\n\nIndependent pass: not needed\n\n## Own attacks\n| SEC ID | Surface | Attack | Must happen |\n| --- | --- | --- | --- |\n\n## Findings\n| # | Severity | Finding | Status | Evidence |\n| --- | --- | --- | --- |\n%s\n' "$2" > "$1/security.md"
}
sec_file "$P" '| 1 | medium | Verbose errors leak the stack | deferred | SEC-01-010 |'$'\n''| 2 | low | Old cookie name | verified | x |'$'\n''| 3 | high | Admin export is unthrottled | open | x |'$'\n''| 4 | high | Demo token never expires | open | x |'$'\n''| 5 | low | Typo in header | open | x |'
printf '\nRisk accepted: #3 high Admin export is unthrottled - internal tool (approved by Sam)\n' >> "$P/security.md"
mkdir -p docs/product/clinic/06-later; printf 'module=clinic\nnumber=06\nprofile=full\nux=yes\nsecurity=attacks\n' > docs/product/clinic/06-later/.plumbline
sec_file docs/product/clinic/06-later '| 1 | low | Late finding | deferred | SEC-06-001 |'
out=$(bash "$G/phase-evidence.sh")
assert "phase-evidence: a security section is there" has "$out" "Security findings deferred or accepted"
assert "phase-evidence: a deferred medium finding, with its feature folder and number" has "$out" "- docs/product/clinic/phases/phase-01 #1 (medium, deferred): Verbose errors leak the stack"
assert "phase-evidence: an accepted high finding" has "$out" "- docs/product/clinic/phases/phase-01 #3 (high, accepted risk): Admin export is unthrottled"
assert "phase-evidence: a medium or low one still open" has "$out" "- docs/product/clinic/phases/phase-01 #5 (low, open): Typo in header"
assert "phase-evidence: findings of another feature are listed too" has "$out" "- docs/product/clinic/06-later #1 (low, deferred): Late finding"
assert "phase-evidence: a verified finding and an unaccepted high one are left out" test -z "$(grep -E 'phase-01 #(2|4) ' <<<"$out")"
out=$(bash "$G/status.sh")
assert "status: the security line counts the deferred findings" has "$out" "· deferred 1 · independent pass not needed"
rm -rf docs/product/clinic/06-later "$P/security.md" "$P/.plumbline"

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

# make-briefs: a core brief per engineer and one file per task, holding only its own ACs.
out=$(bash "$G/make-briefs.sh")
api="$P/briefs/eng-api.md" web="$P/briefs/eng-web.md"
assert "make-briefs: one core brief per engineer" test -f "$api" -a -f "$web"
assert "make-briefs: ...and the output names just those two" test "$(grep -c . <<<"$out")" = 2
assert "make-briefs: brief lists its globs" grep -qF 'apps/api/**' "$api"
assert "make-briefs: a file per task, named by its plan-wide T<n> label" \
  test -f "$P/briefs/eng-api/T1.md" -a -f "$P/briefs/eng-api/T2.md" -a -f "$P/briefs/eng-api/T3.md" -a -f "$P/briefs/eng-web/T4.md"
assert "make-briefs: the core lists a task per line with its file" \
  grep -qxF -- "- T2 [AC-01-002] Reject duplicate room names (NORMAL): $P/briefs/eng-api/T2.md" "$api"
assert "make-briefs: the core holds no AC rows" test -z "$(grep '^| AC-' "$api" "$web")"
assert "make-briefs: a task file holds its own AC rows" grep -q '^| AC-01-002 |' "$P/briefs/eng-api/T2.md"
assert "make-briefs: ...and not another task's" test -z "$(grep -E '^\| AC-01-00[134] \|' "$P/briefs/eng-api/T2.md")"
assert "make-briefs: ...a task citing two criteria holds both rows" \
  test "$(grep -cE '^\| AC-01-00[13] \|' "$P/briefs/eng-api/T1.md")" = 2
assert "make-briefs: brief leaves out other workstreams' ACs" test -z "$(grep -rl '^| AC-01-005 |' "$P/briefs/eng-api" "$api")"
assert "make-briefs: web task holds AC-01-005" grep -q '^| AC-01-005 |' "$P/briefs/eng-web/T4.md"
assert "make-briefs: brief links the full docs" grep -q "^$P/spec.md" "$api"
assert "make-briefs: the core points at the business rules instead of copying them" \
  grep -qF "$P/spec.md, section \"Business rules\"" "$api"
assert "make-briefs: ...no copy of the rules anywhere in the briefs" test -z "$(grep -rF 'Room names are unique within a clinic' "$P/briefs")"
assert "make-briefs: brief carries data and permissions" grep -qF "Only clinic admins can add" "$api"

# A Status that only mentions "pass" doesn't count (a failed row noting a retry).
sed -i.bak -E '0,/\| Pass \|/s//| fail (pass on retry) |/' "$P/test-plan.md" 2>/dev/null; rm -f "$P/test-plan.md.bak"
signoff
assert "signoff-check: a Status like 'fail (pass on retry)' isn't a pass" has "$out" "has no passing test in test-plan.md"

# make-briefs: each engineer's whole task block and its screens' descriptions.
BT=$(mktemp -d); mkdir -p "$BT/.claude" "$BT/docs/product/shop/01-menu"; BF="$BT/docs/product/shop/01-menu"
echo "docs/product/shop/01-menu" > "$BT/.claude/current-phase"
cat > "$BF/dev-plan.md" <<'EOF'
# Feature 01 dev plan

Status: READY

## Team
| Teammate | Model | Workstream | Surface | Effort |
| --- | --- | --- | --- | --- |
| eng-web | sonnet | Menu page | web-ui | medium |
| eng-api | sonnet | Menu API | api | high |
| eng-batch | sonnet | Nightly job | service | low |

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-web | storefront/** |
| eng-api | backend/** |
| eng-batch | jobs/** |

## Contracts
| Contract | Path | Consumers |
| --- | --- | --- |

## Tasks
### eng-web
- [AC-01-001] Show the menu (NORMAL)
  Files: storefront/app/page.tsx
  Red (unit): AC-01-001 renders every item
  E2E: AC-01-001 customer sees the menu
  Done when: unit and e2e tests for AC-01-001 pass
### eng-api
- [AC-01-002] Menu endpoint (HIGH)
  Files: backend/src/menu.js
  Done when: AC-01-002 tests pass
### eng-batch
- [AC-01-003] Nightly cleanup (LOW)
  Files: jobs/cleanup.js
  Done when: AC-01-003 tests pass
EOF
cat > "$BF/acceptance-criteria.md" <<'EOF'
# ACs
| ID | Use case | Given | When | Then | Priority |
| --- | --- | --- | --- | --- | --- |
| AC-01-001 | UC-01-01 | a customer | opens the menu | sees items | P0 |
| AC-01-002 | UC-01-02 | a client | GETs /menu | gets items | P0 |
| AC-01-003 | UC-01-03 | the system | runs nightly | removes old carts | P1 |
EOF
cat > "$BF/ux.md" <<'EOF'
# Feature 01 UX
## Screen inventory
| Screen | Use cases | Purpose | Entered from | Leads to |
| --- | --- | --- | --- | --- |
| Menu | UC-01-01 | Browse | Home | Cart |
| Admin | UC-01-02 | Manage | Login | - |
## Screens
### Menu
Layout: a grid of cards. Copy: "Order now".
### Admin
Layout: a plain table.
EOF
echo "# spec" > "$BF/spec.md"
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
bw="$BF/briefs/eng-web.md" ba="$BF/briefs/eng-api.md" bb="$BF/briefs/eng-batch.md"
tw="$BF/briefs/eng-web/T1.md" ta="$BF/briefs/eng-api/T2.md" tb="$BF/briefs/eng-batch/T3.md"
assert "make-briefs: a task file keeps the task's indented detail lines (Files)" grep -qF 'Files: storefront/app/page.tsx' "$tw"
assert "make-briefs: ...the failing unit test" grep -qF 'Red (unit): AC-01-001 renders every item' "$tw"
assert "make-briefs: ...the e2e test and the done-when" grep -qF 'E2E: AC-01-001 customer sees the menu' "$tw"
assert "make-briefs: ...and done-when" grep -qF 'Done when: unit and e2e tests for AC-01-001 pass' "$tw"
assert "make-briefs: the core has the task line but not its detail lines" \
  test -n "$(grep -F 'T1 [AC-01-001] Show the menu (NORMAL)' "$bw")" -a -z "$(grep -E 'Files:|Red \(unit\)|Done when' "$bw")"
assert "make-briefs: another engineer's task detail stays out" test -z "$(grep -F 'backend/src/menu.js' "$tw" "$bw")"
assert "make-briefs: the task file carries its screen's description" grep -qF 'a grid of cards' "$tw"
assert "make-briefs: ...and not another screen's" test -z "$(grep -F 'a plain table' "$tw")"
assert "make-briefs: the core carries no screens" test -z "$(grep -E 'a grid of cards|a plain table|^## Screens' "$bw" "$ba")"
assert "make-briefs: the api task gets the other screen's text" grep -qF 'a plain table' "$ta"
assert "make-briefs: no prototypes link any more" test -z "$(grep -rF 'prototypes' "$BF/briefs")"
assert "make-briefs: an engineer whose use case has no screen gets no screen text" test -z "$(grep -E 'a grid of cards|a plain table|Screen descriptions' "$tb")"
assert "make-briefs: no attack plan and no SEC IDs, no attacks section" test -z "$(grep -rl 'Attacks to withstand' "$BF/briefs")"

# make-briefs: attacks. Keep the briefs above, then give eng-api SEC IDs.
mkdir -p "$BT/before"; cp -r "$BF/briefs" "$BT/before/briefs"
cp "$BF/dev-plan.md" "$BT/plain-plan.md"
sed -i -e 's/^- \[AC-01-002\] Menu endpoint/- [AC-01-002 SEC-01-001 SEC-01-002] Menu endpoint/' \
       -e 's/^  Done when: AC-01-002 tests pass/&\n  Attacks: SEC-01-001 SEC-01-002/' "$BF/dev-plan.md"
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: SEC IDs without an attack plan add no section" test -z "$(grep -rl 'Attacks to withstand' "$BF/briefs")"
cat >> "$BF/dev-plan.md" <<'EOF'

## Attack plan
Signals: tenancy, authorization
Attack surface: backend/** (GET /menu)
Attack fixtures: backend/test/attack/fixtures.js (second clinic, unauthenticated client) - built in task [AC-01-002 SEC-01-001]
Skipped: "foreign keys": none in this feature

| SEC ID | Surface | Attack | Must happen | Checked |
| --- | --- | --- | --- | --- |
| SEC-01-001 | api | Staff of clinic B calls GET /menu for clinic A | 404, nothing in the body | |
| SEC-01-002 | api | No session calls GET /menu | 401 | |
| SEC-01-003 | web | Another engineer's attack | 403 | |
EOF
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: a task with SEC IDs gets the attacks section" grep -qx '## Attacks to withstand' "$ta"
assert "make-briefs: ...with the Attack fixtures line" grep -qF 'Attack fixtures: backend/test/attack/fixtures.js (second clinic' "$ta"
assert "make-briefs: ...with the table header" grep -q '^| SEC ID | Surface | Attack | Must happen | Checked |$' "$ta"
assert "make-briefs: ...and its own rows" test "$(grep -c '^| SEC-01-00[12] |' "$ta")" = 2
assert "make-briefs: ...but not another engineer's row" test -z "$(grep -r 'SEC-01-003' "$BF/briefs")"
assert "make-briefs: ...nor the plan's Signals, Surface or Skipped lines" test -z "$(grep -E '^(Signals|Attack surface|Skipped):' "$ta")"
assert "make-briefs: the core has no attacks section" test -z "$(grep -l 'Attacks to withstand' "$ba")"
assert "make-briefs: the section follows the acceptance criteria" \
  test "$(grep '^## ' "$ta" | grep -A1 '^## Acceptance criteria' | tail -n1)" = "## Attacks to withstand"
assert "make-briefs: SEC rows stay out of the acceptance criteria section" \
  test -z "$(awk '/^## /{s=($0 ~ /^## Acceptance criteria/)} s' "$ta" | grep 'SEC-')"
assert "make-briefs: engineers without SEC IDs get no section" test -z "$(grep -rl 'Attacks to withstand' "$BF/briefs/eng-web" "$BF/briefs/eng-batch")"
assert "make-briefs: ...and their core and task files are byte-identical to before" \
  bash -c 'cmp -s "$1" "$2/briefs/eng-web.md" && cmp -s "$3" "$2/briefs/eng-web/T1.md" && cmp -s "$4" "$2/briefs/eng-batch.md" && cmp -s "$5" "$2/briefs/eng-batch/T3.md"' _ "$bw" "$BT/before" "$tw" "$bb" "$tb"
cp "$BT/plain-plan.md" "$BF/dev-plan.md"
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: back to a plan without SEC IDs, eng-api's files are as before" \
  bash -c 'cmp -s "$1" "$3/briefs/eng-api.md" && cmp -s "$2" "$3/briefs/eng-api/T2.md"' _ "$ba" "$ta" "$BT/before"

# make-briefs: the workstream's ac-check line names the engineer's SEC IDs too, as does a task's
# tests-only line, and they show for a task with only SEC IDs. They need a profile row for the surface.
mkdir -p "$BT/docs/product"
cat > "$BT/docs/product/project.md" <<'EOF'
# Project profile

## Surfaces
| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |
| --- | --- | --- | --- | --- | --- | --- |
| api | Node | backend/** | | | | node |
EOF
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: no SEC IDs, the core's ac-check command lists the AC IDs only" grep -qF 'ac-check.sh" "AC-01-002" --surface api' "$ba"
assert "make-briefs: ...and the task file's line is tests-only with the same IDs" grep -qF 'ac-check.sh" --tests-only "AC-01-002" --surface api' "$ta"
cp -r "$BF/briefs" "$BT/before/profile"
sed -i -e 's/^- \[AC-01-002\] Menu endpoint/- [AC-01-002 SEC-01-001 SEC-01-002] Menu endpoint/' "$BF/dev-plan.md"
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: with SEC IDs, the core's ac-check command lists AC then SEC IDs" grep -qF 'ac-check.sh" "AC-01-002|SEC-01-001|SEC-01-002" --surface api' "$ba"
assert "make-briefs: ...and so does the task file's tests-only line" \
  grep -qF 'ac-check.sh" --tests-only "AC-01-002|SEC-01-001|SEC-01-002" --surface api' "$ta"
cp "$BT/plain-plan.md" "$BF/dev-plan.md"
sed -i -e 's/AC-01-002/SEC-01-009/g' "$BF/dev-plan.md"
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: an engineer with only SEC IDs still gets the ac-check commands" \
  bash -c 'grep -qF "ac-check.sh\" \"SEC-01-009\" --surface api" "$1" && grep -qF "ac-check.sh\" --tests-only \"SEC-01-009\" --surface api" "$2"' _ "$ba" "$ta"
cp "$BT/plain-plan.md" "$BF/dev-plan.md"
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: back to no SEC IDs, the briefs are byte-identical to the earlier ones" \
  bash -c 'cmp -s "$1" "$3/profile/eng-api.md" && cmp -s "$2" "$3/profile/eng-api/T2.md"' _ "$ba" "$ta" "$BT/before"
# ### headings inside ## Attack plan keep the section open for the brief's rows too.
sed -i -e 's/^- \[AC-01-002\] Menu endpoint/- [AC-01-002 SEC-01-001] Menu endpoint/' "$BF/dev-plan.md"
cat >> "$BF/dev-plan.md" <<'EOF'

## Attack plan
Attack fixtures: backend/test/attack/fixtures.js

### Round 1
| SEC ID | Surface | Attack | Must happen | Checked |
| --- | --- | --- | --- | --- |
| SEC-01-001 | api | Staff of clinic B calls GET /menu for clinic A | 404 | |
EOF
CLAUDE_PROJECT_DIR="$BT" bash "$G/make-briefs.sh" >/dev/null
assert "make-briefs: an attack plan row under a ### heading reaches the task file" grep -q '^| SEC-01-001 |' "$ta"
rm -rf "$BT"


# plan-tasks.sh: the tasks of a dev plan as owner / subject / blocked-by / done-when lines.
PT=$(mktemp -d); mkdir -p "$PT/.claude" "$PT/docs/f1"
echo "docs/f1" > "$PT/.claude/current-phase"
PTD="$PT/docs/f1"
ptplan() { # the lines of a ## Tasks section, as an LF plan
  { printf '# Feature 01 dev plan\n\nStatus: READY\n\n## Team\n| Teammate | Model |\n| --- | --- |\n| eng-api | sonnet |\n\n## Tasks\n'
    printf '%s\n' "$@"; printf '\n## Briefs\nnothing here\n- [AC-09-009] not a task, it is under Briefs (LOW)\n'; } > "$PTD/dev-plan.md"
}
ptrun() { PT_OUT=$(CLAUDE_PROJECT_DIR="$PT" bash "$G/plan-tasks.sh" "$@" 2>"$PT/err"); PT_RC=$?; PT_ERR=$(cat "$PT/err"); }
TAB=$'\t'
ptplan '### lead' \
  '- [chore] L0: Land contracts and the migration' \
  '  Done when: contracts are committed' \
  '### eng-api' \
  '- [AC-02-030 SEC-02-007] B4: Status changes (HIGH)' \
  '  Files: apps/api/status.js' \
  '  Blocked by: B1, L0' \
  '  Done when: the unit and e2e tests for AC-02-030 pass' \
  '- [AC-02-031] B1: Order list (NORMAL)' \
  '  Files: apps/api/list.js' \
  '  Done when: AC-02-031 tests pass'
ptrun
want="lead${TAB}[chore] L0: Land contracts and the migration${TAB}${TAB}contracts are committed${TAB}L0
eng-api${TAB}[AC-02-030 SEC-02-007] B4: Status changes${TAB}B1,L0${TAB}the unit and e2e tests for AC-02-030 pass${TAB}B4
eng-api${TAB}[AC-02-031] B1: Order list${TAB}${TAB}AC-02-031 tests pass${TAB}B1"
assert "plan-tasks: one line per task in plan order: owner, subject without the rating, blocked-by, done-when, label" test "$PT_RC/$PT_OUT" = "0/$want"
assert "plan-tasks: the lead's [chore] lines are included, a task under another heading is not" test "$(grep -c . <<<"$PT_OUT")" = 3
assert "plan-tasks: nothing is written to stderr on success" test -z "$PT_ERR"
ptrun --dir "$PTD"
assert "plan-tasks: --dir names the feature folder" test "$PT_RC/$PT_OUT" = "0/$want"
ptrun --dir="$PTD"
assert "plan-tasks: --dir=value works too" test "$PT_RC/$PT_OUT" = "0/$want"
sed 's/$/\r/' "$PTD/dev-plan.md" > "$PT/crlf.md"; cp "$PTD/dev-plan.md" "$PT/lf.md"; cp "$PT/crlf.md" "$PTD/dev-plan.md"
ptrun
assert "plan-tasks: a CRLF plan gives the same lines, with no carriage returns" test "$PT_RC/$PT_OUT" = "0/$want" -a "$PT_OUT" = "${PT_OUT//$'\r'/}"
cp "$PT/lf.md" "$PTD/dev-plan.md"

# T<n> labels are plan-global; a title starting "S3 bucket" has no colon, so it is not a label.
ptplan '### eng-api' \
  '- [AC-01-001] Create endpoint (NORMAL)' \
  '  Done when: AC-01-001 passes' \
  '- [AC-01-002] S3 bucket for uploads (LOW)' \
  '  Blocked by: T1' \
  '### eng-web' \
  '- [AC-01-003] Upload dialog (NORMAL)' \
  '  Blocked by: T2, T1' \
  '- [AC-01-004] Q2: Quarterly view (LOW)' \
  '  Blocked by: T3'
ptrun
assert "plan-tasks: tasks with no label get T<n> counted across the whole plan, so T3 is in eng-web" \
  test "$PT_RC/$(cut -f3 <<<"$PT_OUT" | paste -sd';' -)" = "0/;T1;T2,T1;T3"
assert "plan-tasks: ...a title that starts with a word and digit but no colon keeps its text" \
  test "$(sed -n 2p <<<"$PT_OUT" | cut -f2)" = "[AC-01-002] S3 bucket for uploads"
assert "plan-tasks: ...an explicit label stays in the subject" test "$(sed -n 4p <<<"$PT_OUT" | cut -f2)" = "[AC-01-004] Q2: Quarterly view"
assert "plan-tasks: a task with no Done when line has an empty fourth field, then its label" \
  test "$(sed -n 2p <<<"$PT_OUT" | awk -F'\t' '{ print NF "/" $4 "/" $5 }')" = "5//T2"
assert "plan-tasks: the fifth field is the label (explicit, or T<n>)" \
  test "$(cut -f5 <<<"$PT_OUT" | paste -sd';' -)" = "T1;T2;T3;Q2"
ptplan '### eng-api' '- [AC-01-001] First (NORMAL)' '- [AC-01-002] Second (NORMAL)'
ptrun
assert "plan-tasks: a plan with no Blocked by lines leaves the third field empty" \
  test "$PT_RC/$(cut -f3 <<<"$PT_OUT" | paste -sd';' -)" = "0/;"

# Bad plans: exit 1, the reason on stderr, nothing on stdout.
ptplan '### eng-api' '- [AC-01-001] B1: First (NORMAL)' '  Blocked by: B7' '- [AC-01-002] B2: Second (NORMAL)'
ptrun
assert "plan-tasks: an unknown Blocked by label exits 1 and names it" test "$PT_RC" = 1 -a -z "$PT_OUT" -a -n "$(grep -F 'Blocked by B7' <<<"$PT_ERR")"
ptplan '### eng-api' '- [AC-01-001] B1: First (NORMAL)' '- [AC-01-002] B1: Second (NORMAL)'
ptrun
assert "plan-tasks: a duplicate label exits 1 and names it" test "$PT_RC" = 1 -a -z "$PT_OUT" -a -n "$(grep -F 'duplicate label B1' <<<"$PT_ERR")"
ptplan '### eng-api' '- [AC-01-001] T2: First (NORMAL)' '- [AC-01-002] Second (NORMAL)'
ptrun
assert "plan-tasks: an explicit label that collides with a later T<n> is a duplicate" test "$PT_RC" = 1 -a -n "$(grep -F 'duplicate label T2' <<<"$PT_ERR")"
ptplan '### eng-api' '- [AC-01-001] B1: First (NORMAL)' '  Blocked by: B1'
ptrun
assert "plan-tasks: a task blocked by itself exits 1" test "$PT_RC" = 1 -a -n "$(grep -F 'blocked by itself' <<<"$PT_ERR")"
ptplan '### eng-api' '- [AC-01-001] B1: First (NORMAL)' '  Blocked by: the API task'
ptrun
assert "plan-tasks: a Blocked by entry that is not a label exits 1" test "$PT_RC" = 1 -a -n "$(grep -F 'is not a label' <<<"$PT_ERR")"
ptplan '### eng-api' '- Write the readme (LOW)'
ptrun
assert "plan-tasks: a subject the task gate would refuse exits 1" test "$PT_RC" = 1 -a -z "$PT_OUT" -a -n "$(grep -F 'names no AC or SEC IDs' <<<"$PT_ERR")"
ptplan '### eng-api' 'No tasks yet.'
ptrun
assert "plan-tasks: a plan with no tasks exits 1" test "$PT_RC" = 1 -a -n "$(grep -F 'no tasks' <<<"$PT_ERR")"
ptrun --dir "$PT/nowhere"
assert "plan-tasks: a missing plan exits 1" test "$PT_RC" = 1 -a -n "$(grep -F 'dev-plan.md is missing' <<<"$PT_ERR")"
ptrun --bogus
assert "plan-tasks: an unknown flag is a usage error" test "$PT_RC" = 2

# Every subject it prints passes the task-created gate (the main fixture repo's plan is READY).
ptplan '### lead' '- [chore] L0: Land contracts' '- [CHORE] Tidy' '### eng-api' '- [AC-01-001 SEC-01-002] B1: First (NORMAL)' '- [SEC-01-003] Second (LOW)' '- [AC-01-004] S3 bucket for uploads (LOW)'
ptrun
gate_ok=0
while IFS= read -r line; do
  subj=$(cut -f2 <<<"$line")
  jq -n --arg s "$subj" '{task_subject: $s}' | bash "$G/task-created-gate.sh" >/dev/null 2>&1 && gate_ok=$((gate_ok + 1))
done <<<"$PT_OUT"
assert "plan-tasks: all five printed subjects are accepted by the task-created gate" test "$PT_RC/$gate_ok" = "0/5"
rm -rf "$PT"

# make-briefs: per-task slices (the core, one file per task, its own criteria, screens and contracts).
SL=$(mktemp -d); mkdir -p "$SL/.claude" "$SL/docs/product/shop/01-menu"; SF="$SL/docs/product/shop/01-menu"
echo "docs/product/shop/01-menu" > "$SL/.claude/current-phase"
slplan() { # extra lines for the end of the plan
  cat > "$SF/dev-plan.md" <<'EOF'
# Feature 01 dev plan

Status: READY

## Team
| Teammate | Model | Workstream | Surface | Effort |
| --- | --- | --- | --- | --- |
| eng-web | sonnet | Menu page | web-ui | medium |
| eng-api | sonnet | Menu API | api | high |
| eng-solo | sonnet | Notes | | low |

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-web | storefront/** |
| eng-api | backend/** |
| eng-solo | notes/** |

## Contracts
| Contract | Path | Consumers |
| --- | --- | --- |
| MenuItem type | contracts/menu.ts | eng-web, eng-api |
| Cart type | contracts/cart.ts | eng-web |
| Audit log | contracts/audit.ts | eng-api |

## Tasks
### lead
- [chore] L0: Land contracts
  Done when: committed
### eng-web
- [AC-01-001] B1: Show the menu (NORMAL)
  Files: storefront/app/page.tsx
  Change: render MenuItem lists from contracts/menu.ts
  Done when: AC-01-001 tests pass
- [AC-01-004] B2: Admin table (HIGH)
  Files: storefront/app/admin.tsx
  Blocked by: B1, L0
  Done when: AC-01-004 tests pass
- [chore] B3: Wire the config
  Files: storefront/config.ts
  Done when: the config loads
### eng-api
- [AC-01-002] Menu endpoint (HIGH)
  Files: backend/src/menu.js
  Done when: AC-01-002 tests pass
EOF
}
slplan
cat > "$SF/acceptance-criteria.md" <<'EOF'
# ACs
| ID | Use case | Given | When | Then | Priority |
| --- | --- | --- | --- | --- | --- |
| AC-01-001 | UC-01-01 | a customer | opens the menu | sees items | P0 |
| AC-01-002 | UC-01-02 | a client | GETs /menu | gets items | P0 |
| AC-01-004 | UC-01-02 | an admin | opens the table | sees rows | P1 |
EOF
cat > "$SF/ux.md" <<'EOF'
# Feature 01 UX
## Screen inventory
| Screen | Use cases | Purpose | Entered from | Leads to |
| --- | --- | --- | --- | --- |
| Menu | UC-01-01 | Browse | Home | Cart |
| Admin | UC-01-02 | Manage | Login | - |
## Screens
### Menu
Layout: a grid of cards.
### Admin
Layout: a plain table.
EOF
cat > "$SF/spec.md" <<'EOF'
# spec

## Business rules
Rule: items are priced in cents.

| Rule | Cases |
| --- | --- |
| R1 | UC-01-02: hidden items show to admins (AC-01-004) |
| R2 | UC-01-01: sold-out items are greyed out |

## Data and permissions
Only admins edit.
EOF
sl() { CLAUDE_PROJECT_DIR="$SL" bash "$G/make-briefs.sh" 2>"$SL/err"; SL_RC=$?; SL_ERR=$(cat "$SL/err"); }
sl >/dev/null
B1="$SF/briefs/eng-web/B1.md" B2="$SF/briefs/eng-web/B2.md" B3="$SF/briefs/eng-web/B3.md" core="$SF/briefs/eng-web.md"
assert "make-briefs: files are named by the explicit labels, T<n> for a task without one (plan-wide)" \
  test -f "$B1" -a -f "$B2" -a -f "$B3" -a -f "$SF/briefs/eng-api/T5.md" -a ! -e "$SF/briefs/eng-solo"
assert "make-briefs: the core's task list is in plan order, one line per task, with IDs, rating, blockers and file" \
  test "$(grep -E '^- (B1|B2|B3) ' "$core" | sed "s|docs/product/shop/01-menu/||")" = "- B1 [AC-01-001] Show the menu (NORMAL): briefs/eng-web/B1.md
- B2 [AC-01-004] Admin table (HIGH), after B1, L0: briefs/eng-web/B2.md
- B3 [chore] Wire the config: briefs/eng-web/B3.md"
assert "make-briefs: a task file holds only its own criteria" \
  test -n "$(grep '^| AC-01-001 |' "$B1")" -a -z "$(grep '^| AC-01-004 |' "$B1")" -a -n "$(grep '^| AC-01-004 |' "$B2")" -a -z "$(grep '^| AC-01-001 |' "$B2")"
assert "make-briefs: ...and only the screens its use cases cite" \
  test -n "$(grep 'a grid of cards' "$B1")" -a -z "$(grep 'a plain table' "$B1")" -a -n "$(grep 'a plain table' "$B2")" -a -z "$(grep 'a grid of cards' "$B2")"
assert "make-briefs: ...the screen inventory is cut to those rows too" \
  test -n "$(grep '^| Menu |' "$B1")" -a -z "$(grep '^| Admin |' "$B1")"
assert "make-briefs: a [chore] task gets no screens and no criteria" \
  test -z "$(grep -E 'a grid of cards|a plain table|^## Screens|^\| AC-' "$B3")" -a -n "$(grep -F 'Files: storefront/config.ts' "$B3")"
assert "make-briefs: ...and no ac-check line (nothing to test)" test -z "$(grep ac-check "$B3")"
assert "make-briefs: a task file holds its whole block, with its Blocked by line" grep -qF 'Blocked by: B1, L0' "$B2"
assert "make-briefs: a task's contracts are the ones its block mentions" \
  test -n "$(grep 'contracts/menu.ts' "$B1")" -a -z "$(grep -E 'contracts/(cart|audit)' "$B1")" -a -z "$(grep '^| MenuItem' "$B2")"
assert "make-briefs: the core lists the contracts for its consumer" \
  test -n "$(grep '^| MenuItem type' "$core")" -a -n "$(grep '^| Cart type' "$core")" -a -z "$(grep '^| Audit log' "$core")"
assert "make-briefs: the core points at the business rules instead of copying them" \
  test -n "$(grep -F 'section "Business rules"' "$core")" -a -z "$(grep -rF 'priced in cents' "$SF/briefs")"
assert "make-briefs: ...and keeps data and permissions" grep -qF 'Only admins edit.' "$core"
RULES_TAIL="All rules: spec.md, '## Business rules' (read it if a case isn't covered above)."
assert "make-briefs: every task file has a Rules section ending with the pointer to all rules" \
  test "$(grep -c '^## Rules$' "$B1")" = 1 -a "$(grep -c '^## Rules$' "$B3")" = 1 -a "$(grep -cF "$RULES_TAIL" "$B1")" = 1 -a "$(grep -cF "$RULES_TAIL" "$B3")" = 1 \
    -a "$(grep -cF "$RULES_TAIL" "$SF/briefs/eng-api/T5.md")" = 1
assert "make-briefs: a task's Rules hold the rows citing its use cases or criteria, under the table header" \
  test -n "$(grep -F '| R2 |' "$B1")" -a -z "$(grep -F '| R1 |' "$B1")" -a -n "$(grep -F '| R1 |' "$B2")" -a -z "$(grep -F '| R2 |' "$B2")" \
    -a "$(grep -cF '| Rule | Cases |' "$B1")" = 1
assert "make-briefs: a [chore] cites nothing, so its Rules are just the pointer" \
  test -z "$(grep -F '| R' "$B3")" -a "$(sed -n '/^## Rules$/,$p' "$B3" | grep -c .)" = 2
assert "make-briefs: an engineer with no tasks gets a core with an empty task list and no folder" \
  test -n "$(grep -F '(none listed in dev-plan.md)' "$SF/briefs/eng-solo.md")"
assert "make-briefs: no warning for small task files" test -z "$SL_ERR"

# Stale task files go; a renamed label leaves only the new file; a long task warns.
touch "$SF/briefs/eng-web/OLD.md"
sed -i 's/ B2: Admin table/ B9: Admin table/' "$SF/dev-plan.md"
sl >/dev/null
assert "make-briefs: the engineer's folder is cleared before it is written again" \
  test ! -e "$SF/briefs/eng-web/OLD.md" -a ! -e "$B2" -a -f "$SF/briefs/eng-web/B9.md"
sed -i 's/ B9: Admin table/ B2: Admin table/' "$SF/dev-plan.md"
{ printf '  Change: '; head -c 21000 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$SL/long.txt"
sed -i "/^  Files: storefront\/app\/page.tsx\$/r $SL/long.txt" "$SF/dev-plan.md"
sl >/dev/null
assert "make-briefs: a task file over 20 KB warns on stderr, naming the file" \
  test "$SL_RC" = 0 -a -n "$(grep -F "warning: " <<<"$SL_ERR" | grep -F "briefs/eng-web/B1.md")" -a -n "$(grep -F '(over 20 KB)' <<<"$SL_ERR")"
assert "make-briefs: ...and only that file" test "$(grep -c warning <<<"$SL_ERR")" = 1
assert "make-briefs: ...and the core stays small" test "$(wc -c < "$core")" -lt 4000

# Plans with labels that don't work stop the run before any brief is written.
rm -rf "$SF/briefs"
slplan
sed -i 's/ B2: Admin table/ B1: Admin table/' "$SF/dev-plan.md"
sl >/dev/null
assert "make-briefs: a duplicate label exits 1 and writes nothing" \
  test "$SL_RC" = 1 -a -n "$(grep -F 'duplicate label B1' <<<"$SL_ERR")" -a -z "$(ls "$SF/briefs" 2>/dev/null)"
slplan
sed -i 's/Blocked by: B1, L0/Blocked by: B8/' "$SF/dev-plan.md"
sl >/dev/null
assert "make-briefs: an unknown Blocked by label exits 1" test "$SL_RC" = 1 -a -n "$(grep -F 'Blocked by B8' <<<"$SL_ERR")"
slplan
sed 's/$/\r/' "$SF/dev-plan.md" > "$SL/crlf.md"; cp "$SL/crlf.md" "$SF/dev-plan.md"
sl >/dev/null
assert "make-briefs: a CRLF plan makes the same task files" \
  test "$SL_RC" = 0 -a -f "$B1" -a -f "$B2" -a -n "$(grep '^| AC-01-004 |' "$B2")"
rm -rf "$SL"

# context.sh points an engineer at its core brief and its task folder.
cj() { jq -r '.hookSpecificOutput.additionalContext' <<<"$(echo '{"hook_event_name":"SubagentStart","agent_id":"aeng-api-0123456789abcdef","agent_type":"general-purpose"}' | bash "$G/context.sh" 2>/dev/null)"; }
ctxout=$(cj)
assert "context: names the core brief and the task folder" has "$ctxout" "Your brief: $P/briefs/eng-api.md (core); your tasks: $P/briefs/eng-api/."
assert "context: ...and says to read the core once and a task's file when starting it" has "$ctxout" "Read the core once and the current task's file when you start it"
rm -rf "$P/briefs/eng-api"
assert "context: without a task folder it keeps the old one-file pointer" has "$(cj)" "Your brief: $P/briefs/eng-api.md. Read it before anything else"

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
