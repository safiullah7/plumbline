#!/usr/bin/env bash
# Self-test for kickoff.sh: the legacy <area> phase-NN form (v0.3's file set,
# exactly) and the module form (Standard and Full, new and existing modules,
# repo-wide numbering across both layouts, --no-ux, the standard overlay,
# .plumbline, errors that change nothing). Run from the repo root:
#   bash tests/kickoff-selftest.sh
# Works in bash on macOS and Linux, and in Git Bash on Windows.
set -u
ROOT="$(cd "$(dirname "${0//\\//}")/.." && pwd)"
G="$ROOT/plugins/plumbline/scripts"
TPL="$ROOT/plugins/plumbline/skills/kickoff/templates"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo" && cd "$T/repo"
export HOME="$T" CLAUDE_PROJECT_DIR="$T/repo"
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_DATA
source "$G/lib.sh"

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
assert() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
eq() { # name, got, expected
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (got '$2', expected '$3')"; fi
}
kickoff() { bash "$G/kickoff.sh" "$@"; }
# Every file under the repo, sorted, so a case can assert exactly what changed.
tree() { (cd "$T/repo" && find . -type f | sed 's|^\./||' | LC_ALL=C sort); }
snapshot() { (cd "$T/repo" && find . -type f -exec cksum {} + | LC_ALL=C sort); }
same_as() { # file, template, sed expressions...: the template with only these replaced
  local f="$1" t="$2"; shift 2
  [[ "$(cat "$f")" == "$(sed "$@" "$t")" ]]
}
cur() { head -n1 .claude/current-phase; }

# --- Legacy form: v0.3's kickoff, exactly ---
out=$(kickoff clinic phase-01); rc=$?
eq "legacy: exit 0" "$rc" 0
P=docs/product/clinic/phases/phase-01
eq "legacy: prints the phase folder" "$(tail -n1 <<<"$out")" "$P"
expected=".claude/current-phase
docs/product/clinic/decisions.md
docs/product/clinic/design-principles.md
$P/acceptance-criteria.md
$P/briefs/.gitkeep
$P/contracts/.gitkeep
$P/dev-plan.md
$P/progress.md
$P/prototypes/.gitkeep
$P/qa-report.md
$P/questions.md
$P/signoff.md
$P/spec.md
$P/test-plan.md
$P/ux.md
docs/product/clinic/vision.md"
eq "legacy: exactly v0.3's file set" "$(tree)" "$(LC_ALL=C sort <<<"$expected")"
assert "legacy: no .plumbline" test ! -e "$P/.plumbline"
eq "legacy: current-phase is the folder, one line" "$(cat .claude/current-phase)" "$P"
eq "legacy: vision title has the area name" "$(head -n1 docs/product/clinic/vision.md)" "# Clinic vision"
assert "legacy: AC-01-001 in acceptance-criteria.md" grep -q 'AC-01-001' "$P/acceptance-criteria.md"
assert "legacy: area docs are the templates with <Area>/<area> filled" bash -c "
  for f in vision decisions design-principles; do
    [[ \"\$(cat docs/product/clinic/\$f.md)\" == \"\$(sed -e 's/<Area>/Clinic/g' -e 's/<area>/clinic/g' '$TPL/area/'\$f.md)\" ]] || exit 1
  done"
assert "legacy: design-principles points at the area's tokens.css" \
  grep -q 'docs/product/clinic/tokens.css' docs/product/clinic/design-principles.md
bad=0
for t in "$TPL"/phase/*; do same_as "$P/${t##*/}" "$t" -e 's/<phase>/01/g' || bad=1; done
eq "legacy: phase docs are the templates with <phase> filled" "$bad" 0
assert "legacy: no <phase> left" bash -c "! grep -rq '<phase>' '$P'"
assert "legacy: Design verification box kept" grep -q '^- \[ \] Design verification' "$P/signoff.md"

before=$(snapshot)
kickoff clinic phase-01 >/dev/null 2>&1; rc=$?
eq "legacy: an existing phase folder exits 1" "$rc" 1
eq "legacy: ...and changes nothing" "$(snapshot)" "$before"

echo "# Clinic vision, edited" > docs/product/clinic/vision.md
out=$(kickoff clinic phase-02); rc=$?
eq "legacy: second phase exit 0" "$rc" 0
eq "legacy: area docs never overwritten" "$(cat docs/product/clinic/vision.md)" "# Clinic vision, edited"
assert "legacy: no 'added' lines when the area docs exist" bash -c "! grep -q '^added' <<<'$out'"
eq "legacy: current-phase moves to the new phase" "$(cur)" docs/product/clinic/phases/phase-02

# v0.3's hand kickoff took these names; refuse only what breaks a path or sed.
out=$(kickoff Vet_Records phase-01); rc=$?
eq "legacy: mixed-case area with an underscore: exit 0" "$rc" 0
eq "legacy: ...folder keeps the name as given" "$(tail -n1 <<<"$out")" docs/product/Vet_Records/phases/phase-01
eq "legacy: ...area title keeps the name" "$(head -n1 docs/product/Vet_Records/vision.md)" "# Vet_Records vision"
out=$(kickoff vet phase-3); rc=$?
eq "legacy: one-digit phase: exit 0" "$rc" 0
eq "legacy: ...folder is phase-3" "$(tail -n1 <<<"$out")" docs/product/vet/phases/phase-3
assert "legacy: ...<phase> is 3" grep -q 'AC-3-001' docs/product/vet/phases/phase-3/acceptance-criteria.md
out=$(kickoff vet phase-03-auth); rc=$?
eq "legacy: phase id with a suffix: exit 0" "$rc" 0
eq "legacy: ...folder keeps the suffix" "$(tail -n1 <<<"$out")" docs/product/vet/phases/phase-03-auth
assert "legacy: ...<phase> is the leading number" grep -q 'AC-03-001' docs/product/vet/phases/phase-03-auth/acceptance-criteria.md
assert "legacy: ...title keeps Phase" grep -q '^# Phase 03' docs/product/vet/phases/phase-03-auth/spec.md
before=$(snapshot)
for bad in "a/b phase-01" "vet phase-1/x" "vet phase-1&" ".. phase-01" ".hid phase-01"; do
  kickoff $bad >/dev/null 2>&1; eq "legacy: refuses '$bad'" "$?" 1
done
kickoff 'a\b' phase-05 >/dev/null 2>&1; eq "legacy: refuses a backslash" "$?" 1
kickoff "va t" phase-05 >/dev/null 2>&1; eq "legacy: refuses a name with a space" "$?" 1
kickoff vet "phase-5 x" >/dev/null 2>&1; eq "legacy: refuses a phase id with a space" "$?" 1
eq "legacy: refused names change nothing" "$(snapshot)" "$before"
kickoff clinic phase-04 --no-ux >/dev/null 2>&1; eq "legacy: options are a usage error" "$?" 1
assert "legacy: ...and create nothing" test ! -e docs/product/clinic/phases/phase-04

# --- Module form ---
rm -rf docs .claude
# An existing module with its own docs.
mkdir -p docs/product/rooms
for f in vision design-principles decisions changes; do echo "# rooms $f, ours" > "docs/product/rooms/$f.md"; done
before=$(cat docs/product/rooms/*.md)
out=$(kickoff rooms room-schedules --profile standard); rc=$?
F=docs/product/rooms/01-room-schedules
eq "standard, existing module: exit 0" "$rc" 0
eq "standard, existing module: last line is the folder" "$(tail -n1 <<<"$out")" "$F"
eq "standard, existing module: only the folder line printed" "$out" "$F"
eq "standard, existing module: module docs not overwritten" "$(cat docs/product/rooms/*.md)" "$before"
eq "standard, existing module: current-phase" "$(cur)" "$F"
eq "standard: feature files" "$(cd "$F" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | paste -sd' ' -)" \
  ".plumbline acceptance-criteria.md briefs/.gitkeep contracts/.gitkeep dev-plan.md progress.md prototypes/.gitkeep qa-report.md questions.md signoff.md spec.md test-plan.md ux.md"
subst=(-e 's/Phase <phase>/Feature 01/g' -e 's/<phase>/01/g' -e 's/<Module>/Rooms/g' -e 's/<module>/rooms/g')
assert "standard: spec.md is the slim overlay" same_as "$F/spec.md" "$TPL/standard/spec.md" "${subst[@]}"
assert "standard: test-plan.md is the overlay" same_as "$F/test-plan.md" "$TPL/standard/test-plan.md" "${subst[@]}"
assert "standard: slim spec has Data and permissions" grep -q '^## Data and permissions' "$F/spec.md"
assert "standard: slim spec has no Use cases section" bash -c "! grep -q '^### UC-' '$F/spec.md'"
assert "standard: test plan has Evidence" grep -q '^## Evidence' "$F/test-plan.md"
assert "standard: other docs are the phase templates" same_as "$F/dev-plan.md" "$TPL/phase/dev-plan.md" "${subst[@]}"
assert "standard: ux kept the Design verification box" grep -q '^- \[ \] Design verification' "$F/signoff.md"
eq "standard: .plumbline" "$(cat "$F/.plumbline")" "module=rooms
number=01
profile=standard
ux=yes
created=$(date +%Y-%m-%d)
slug=room-schedules"
eq "feature_meta: module" "$(feature_meta module)" rooms
eq "feature_meta: number" "$(feature_meta number)" 01
eq "feature_meta: profile" "$(feature_meta profile)" standard
eq "feature_meta: ux" "$(feature_meta ux)" yes
eq "feature_meta: no surfaces without --surfaces" "$(feature_meta surfaces)" ""
eq "feature_meta: created" "$(feature_meta created)" "$(date +%Y-%m-%d)"
eq "feature_meta: slug" "$(feature_meta slug)" room-schedules
eq "module form: docs say Feature, not Phase, in their titles" \
  "$(cd "$F" && head -qn1 *.md | grep -c "^# Feature 01")" 9
assert "module form: no 'Phase 01' left in the copied docs" bash -c "! grep -rq 'Phase 01' '$F'"

# Standard creating a missing module, without UX, with surfaces.
out=$(kickoff billing-ops invoice-export --profile=standard --no-ux --surfaces api,cli); rc=$?
F=docs/product/billing-ops/02-invoice-export
eq "standard, missing module: exit 0" "$rc" 0
eq "standard, missing module: last line is the folder" "$(tail -n1 <<<"$out")" "$F"
eq "standard, missing module, no UX: module docs added" "$(ls docs/product/billing-ops | paste -sd' ' -)" \
  "02-invoice-export changes.md decisions.md vision.md"
eq "standard, missing module: 'added' lines for each" "$(grep -c '^added docs/product/billing-ops/' <<<"$out")" 3
eq "module docs: <Module> is the display name" "$(head -n1 docs/product/billing-ops/vision.md)" "# Billing ops vision"
assert "module docs: vision.md is the template with placeholders filled" same_as docs/product/billing-ops/vision.md \
  "$TPL/module/vision.md" -e 's/<Module>/Billing ops/g' -e 's/<module>/billing-ops/g'
assert "no UX: no ux.md" test ! -e "$F/ux.md"
assert "no UX: no prototypes/" test ! -e "$F/prototypes"
assert "no UX: contracts/ and briefs/ kept" test -f "$F/contracts/.gitkeep" -a -f "$F/briefs/.gitkeep"
assert "no UX: no Design verification box" bash -c "! grep -q 'Design verification' '$F/signoff.md'"
assert "no UX: signoff.md otherwise unchanged" same_as "$F/signoff.md" "$TPL/phase/signoff.md" \
  -e 's/Phase <phase>/Feature 02/g' -e 's/<phase>/02/g' -e '/^- \[ \] Design verification/d'
eq "no UX: signoff.md lost exactly one line" \
  "$(( $(wc -l < "$TPL/phase/signoff.md") - $(wc -l < "$F/signoff.md") ))" 1
eq "feature_meta: surfaces" "$(feature_meta surfaces)" api,cli
eq "feature_meta: ux=no" "$(feature_meta ux)" no
eq "feature_meta: profile standard" "$(feature_meta profile)" standard
assert ".plumbline: module line" grep -qx 'module=billing-ops' "$F/.plumbline"
eq ".plumbline: surfaces line before ux" "$(sed -n 4p "$F/.plumbline")" surfaces=api,cli

# Full with --new-module.
out=$(kickoff vet-records intake --new-module); rc=$?
F=docs/product/vet-records/03-intake
eq "full, new module: exit 0" "$rc" 0
eq "full, new module: last line is the folder" "$(tail -n1 <<<"$out")" "$F"
eq "full, new module: all four module docs" "$(ls docs/product/vet-records | paste -sd' ' -)" \
  "03-intake changes.md decisions.md design-principles.md vision.md"
assert "full: spec.md is the full phase template" same_as "$F/spec.md" "$TPL/phase/spec.md" \
  -e 's/Phase <phase>/Feature 03/g' -e 's/<phase>/03/g' -e 's/<Module>/Vet records/g' -e 's/<module>/vet-records/g'
assert "full: ux.md and prototypes/" test -f "$F/ux.md" -a -f "$F/prototypes/.gitkeep"
assert "full: AC-03-001" grep -q 'AC-03-001' "$F/acceptance-criteria.md"
eq "feature_meta: profile full" "$(feature_meta profile)" full
eq "feature_meta: module vet-records" "$(feature_meta module)" vet-records

# Full in an existing module.
echo "# vet-records vision, ours" > docs/product/vet-records/vision.md
out=$(kickoff vet-records follow-ups --profile full --ux); rc=$?
F=docs/product/vet-records/04-follow-ups
eq "full, existing module: exit 0" "$rc" 0
eq "full, existing module: last line is the folder" "$(tail -n1 <<<"$out")" "$F"
eq "full, existing module: vision.md not overwritten" "$(cat docs/product/vet-records/vision.md)" "# vet-records vision, ours"
eq "full, existing module: current-phase" "$(cur)" "$F"

# --new-module on an existing module.
before=$(snapshot)
kickoff rooms another --new-module >/dev/null 2>&1; rc=$?
eq "--new-module on an existing module: exit 2" "$rc" 2
eq "--new-module on an existing module: nothing changed" "$(snapshot)" "$before"

# Errors change nothing.
kickoff rooms room-schedules >/dev/null 2>&1; rc=$?
eq "existing feature folder (same slug): exit 1" "$rc" 1
kickoff rooms Bad_Slug >/dev/null 2>&1; rc=$?
eq "invalid slug: exit 1" "$rc" 1
kickoff Rooms x >/dev/null 2>&1; rc=$?
eq "invalid module: exit 1" "$rc" 1
kickoff rooms -x >/dev/null 2>&1; rc=$?
eq "unknown option: exit 1" "$rc" 1
kickoff rooms x --profile quick >/dev/null 2>&1; rc=$?
eq "bad profile: exit 1" "$rc" 1
kickoff rooms x --surfaces 'api,,web' >/dev/null 2>&1; rc=$?
eq "bad surfaces: exit 1" "$rc" 1
kickoff rooms >/dev/null 2>&1; rc=$?
eq "one argument: exit 1" "$rc" 1
out=$(kickoff 2>&1); rc=$?
eq "no arguments: exit 1" "$rc" 1
assert "no arguments: prints usage" grep -q '^usage: kickoff.sh' <<<"$out"
eq "errors: nothing changed" "$(snapshot)" "$before"

# Numbering continues across modules and legacy phases/ folders.
rm -rf docs .claude
mkdir -p docs/product/demo/phases/phase-03 docs/product/rooms/04-x
out=$(kickoff rooms y); rc=$?
eq "numbering: legacy phase-03 + rooms/04-x -> 05" "$(tail -n1 <<<"$out")" docs/product/rooms/05-y
out=$(kickoff billing z)
eq "numbering: continues in another module -> 06" "$(tail -n1 <<<"$out")" docs/product/billing/06-z
out=$(kickoff demo phase-07)
out=$(kickoff rooms w)
eq "numbering: after a legacy kickoff -> 08" "$(tail -n1 <<<"$out")" docs/product/rooms/08-w

# A new feature in a legacy area goes into its phases/ folder (dev plan §6.2).
out=$(kickoff demo checkin --profile standard); rc=$?
F=docs/product/demo/phases/phase-09
eq "legacy area: exit 0" "$rc" 0
eq "legacy area: next number under phases/" "$(tail -n1 <<<"$out")" "$F"
eq "legacy area: module_dir is the area" "$(module_dir)" "$PROJECT_DIR/docs/product/demo"
eq "legacy area: .plumbline module" "$(feature_meta module)" demo
eq "legacy area: next number after it -> 10" "$(next_feature_number)" 10

# The same feature twice in a legacy area is refused too: its folders are numbered
# phase-NN, so the slug is kept in .plumbline.
eq "legacy area: .plumbline keeps the slug" "$(feature_meta slug)" checkin
eq "legacy area: docs say Feature" "$(head -n1 "$F/spec.md" | cut -d: -f1)" "# Feature 09"
before=$(snapshot); was=$(cur)
out=$(kickoff demo checkin --profile standard 2>&1); rc=$?
eq "legacy area, same slug: exit 1" "$rc" 1
assert "legacy area, same slug: names the existing folder" grep -q "^kickoff: $F already exists; nothing changed.$" <<<"$out"
eq "legacy area, same slug: nothing changed" "$(snapshot)" "$before"
eq "legacy area, same slug: current-phase unchanged" "$(cur)" "$was"
printf 'module=demo\r\nslug=crlf-one\r\n' > docs/product/demo/phases/phase-09/.plumbline
kickoff demo crlf-one >/dev/null 2>&1; eq "legacy area, same slug in a CRLF .plumbline: exit 1" "$?" 1
printf 'module=demo\nslug=checkin\n' > docs/product/demo/phases/phase-09/.plumbline
out=$(kickoff demo checkin-2); rc=$?
eq "legacy area: a different slug is fine" "$rc/$(tail -n1 <<<"$out")" "0/docs/product/demo/phases/phase-10"
kickoff demo checkin >/dev/null 2>&1; eq "legacy area: old slug still refused after a newer feature" "$?" 1
out=$(kickoff demo phase-11); rc=$?
eq "legacy area: a legacy-form phase has no slug and doesn't block" "$rc" 0

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
