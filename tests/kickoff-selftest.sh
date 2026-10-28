#!/usr/bin/env bash
# Self-test for kickoff.sh: the legacy <area> phase-NN form (v0.3's file set,
# exactly) and the module form (Standard and Full, new and existing modules,
# repo-wide numbering across both layouts, --no-ux, the standard overlay,
# .plumbline, --surfaces: overlays, the UX default, unknown names; errors that
# change nothing). Run from the repo root:
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
bad=0
for t in "$TPL"/phase/*; do same_as "$P/${t##*/}" "$t" -e 's/<phase>/01/g' || bad=1; done
eq "legacy: phase docs are the templates with <phase> filled" "$bad" 0
assert "legacy: no <phase> left" bash -c "! grep -rq '<phase>' '$P'"

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
  ".plumbline acceptance-criteria.md briefs/.gitkeep contracts/.gitkeep dev-plan.md progress.md qa-report.md questions.md signoff.md spec.md test-plan.md ux.md"
subst=(-e 's/Phase <phase>/Feature 01/g' -e 's/<phase>/01/g' -e 's/<Module>/Rooms/g' -e 's/<module>/rooms/g')
assert "standard: spec.md is the slim overlay" same_as "$F/spec.md" "$TPL/standard/spec.md" "${subst[@]}"
assert "standard: test-plan.md is the overlay" same_as "$F/test-plan.md" "$TPL/standard/test-plan.md" "${subst[@]}"
assert "standard: slim spec has Data and permissions" grep -q '^## Data and permissions' "$F/spec.md"
assert "standard: slim spec has no Use cases section" bash -c "! grep -q '^### UC-' '$F/spec.md'"
assert "standard: other docs are the phase templates" same_as "$F/dev-plan.md" "$TPL/phase/dev-plan.md" "${subst[@]}"
assert "standard: ux.md kept, no prototypes/ in the module form" test -f "$F/ux.md" -a ! -e "$F/prototypes"
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
assert "no UX: signoff.md is the template" same_as "$F/signoff.md" "$TPL/phase/signoff.md" \
  -e 's/Phase <phase>/Feature 02/g' -e 's/<phase>/02/g'
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
assert "full: ux.md, and no prototypes/" test -f "$F/ux.md" -a ! -e "$F/prototypes"
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

# --- Surfaces: overlays and the UX default ---
rm -rf docs .claude
# mobile-ui: UX by default; ux.md gets the mobile section once.
out=$(kickoff shop checkout --surfaces mobile-ui); rc=$?
F=docs/product/shop/01-checkout
eq "surfaces mobile-ui: exit 0" "$rc" 0
eq "surfaces mobile-ui: last line is the folder" "$(tail -n1 <<<"$out")" "$F"
assert "surfaces mobile-ui: UX by default, ux.md and no prototypes/" test -f "$F/ux.md" -a ! -e "$F/prototypes"
eq "surfaces mobile-ui: mobile section appended once" "$(grep -c '^## Mobile design rules' "$F/ux.md")" 1
assert "surfaces mobile-ui: the template's Screen inventory is still there" grep -q '^## Screen inventory' "$F/ux.md"
want=$({ sed -e 's/Phase <phase>/Feature 01/g' -e 's/<phase>/01/g' -e 's/<Module>/Shop/g' -e 's/<module>/shop/g' "$TPL/phase/ux.md"; echo; cat "$TPL/surface/mobile/ux.append.md"; })
eq "surfaces mobile-ui: ux.md is the template, a blank line, then the overlay" "$(cat "$F/ux.md")" "$want"
assert "surfaces mobile-ui: only ux.md got the section" bash -c "! grep -rq 'Mobile design rules' '$F' --exclude=ux.md"
eq "surfaces mobile-ui: .plumbline surfaces" "$(feature_meta surfaces)" mobile-ui
eq "surfaces mobile-ui: .plumbline ux" "$(feature_meta ux)" yes
eq "surfaces mobile-ui: no <phase> left" "$(grep -rl '<phase>' "$F" | wc -l | tr -d ' ')" 0

# mobile-ui with --no-ux: no ux.md, so no ux append.
out=$(kickoff shop wallet --surfaces mobile-ui --no-ux); rc=$?
F=docs/product/shop/02-wallet
eq "surfaces mobile-ui --no-ux: exit 0" "$rc" 0
assert "surfaces mobile-ui --no-ux: no ux.md" test ! -e "$F/ux.md"
assert "surfaces mobile-ui --no-ux: no mobile section anywhere" bash -c "! grep -rq 'Mobile design rules' '$F'"
eq "surfaces mobile-ui --no-ux: ux=no" "$(feature_meta ux)" no

# api alone: no UX by default; the overlay's contracts/README.md and test-plan section.
out=$(kickoff shop orders-api --surfaces api); rc=$?
F=docs/product/shop/03-orders-api
eq "surfaces api: exit 0" "$rc" 0
assert "surfaces api: UX defaults to no (no ux.md, no prototypes/)" test ! -e "$F/ux.md" -a ! -e "$F/prototypes"
eq "surfaces api: ux=no in .plumbline" "$(feature_meta ux)" no
assert "surfaces api: contracts/README.md copied next to .gitkeep" test -f "$F/contracts/README.md" -a -f "$F/contracts/.gitkeep"
assert "surfaces api: README is the template with placeholders filled" same_as "$F/contracts/README.md" "$TPL/surface/api/contracts/README.md" \
  -e 's/Phase <phase>/Feature 03/g' -e 's/<phase>/03/g' -e 's/<Module>/Shop/g' -e 's/<module>/shop/g'
assert "surfaces api: README says Feature 03, module shop" grep -q '^Feature 03, module shop\.' "$F/contracts/README.md"
eq "surfaces api: API evidence plan appended once" "$(grep -c '^## API evidence plan' "$F/test-plan.md")" 1
assert "surfaces api: the full test plan's own sections are kept" grep -q '^## Traceability' "$F/test-plan.md"
n=$(wc -l < "$TPL/surface/api/test-plan.append.md")
eq "surfaces api: test-plan ends with the overlay" "$(tail -n "$n" "$F/test-plan.md")" "$(tail -n "$n" "$TPL/surface/api/test-plan.append.md")"

# api with an explicit --ux wins over the default.
out=$(kickoff shop orders-ui --surfaces api --ux); rc=$?
F=docs/product/shop/04-orders-ui
eq "surfaces api --ux: exit 0" "$rc" 0
assert "surfaces api --ux: ux.md and no prototypes/" test -f "$F/ux.md" -a ! -e "$F/prototypes"
eq "surfaces api --ux: ux=yes" "$(feature_meta ux)" yes
assert "surfaces api --ux: no mobile section" bash -c "! grep -q 'Mobile design rules' '$F/ux.md'"

# ai: spec and test-plan sections, once each.
out=$(kickoff shop assistant --surfaces ai); rc=$?
F=docs/product/shop/05-assistant
eq "surfaces ai: exit 0" "$rc" 0
eq "surfaces ai: spec section once" "$(grep -c '^## Model, prompts and limits' "$F/spec.md")" 1
eq "surfaces ai: test-plan section once" "$(grep -c '^## Eval set' "$F/test-plan.md")" 1
assert "surfaces ai: no ux.md" test ! -e "$F/ux.md"
assert "surfaces ai: no contracts/README.md" test ! -e "$F/contracts/README.md"

# cli on the standard profile: the append comes after the profile overlay's spec.
out=$(kickoff shop export-cli --surfaces cli --profile standard); rc=$?
F=docs/product/shop/06-export-cli
eq "surfaces cli standard: exit 0" "$rc" 0
eq "surfaces cli standard: command surface once" "$(grep -c '^## Command surface' "$F/spec.md")" 1
assert "surfaces cli standard: spec keeps the slim overlay (Data and permissions)" grep -q '^## Data and permissions' "$F/spec.md"
eq "surfaces cli standard: command surface is last in spec.md" "$(tail -n 3 "$F/spec.md")" "$(tail -n 3 "$TPL/surface/cli/spec.append.md")"
assert "surfaces cli standard: no ux.md" test ! -e "$F/ux.md"

# Several surfaces: two of a kind apply their overlay once; names are kept as given.
out=$(kickoff shop multi --surfaces web-ui-shop,api,api-admin,cli,mobile-ui,mobile-ui-kiosk); rc=$?
F=docs/product/shop/07-multi
eq "surfaces multi: exit 0" "$rc" 0
eq "surfaces multi: .plumbline keeps the names as given" "$(feature_meta surfaces)" web-ui-shop,api,api-admin,cli,mobile-ui,mobile-ui-kiosk
eq "surfaces multi: api overlay once (test-plan)" "$(grep -c '^## API evidence plan' "$F/test-plan.md")" 1
eq "surfaces multi: mobile overlay once (ux.md)" "$(grep -c '^## Mobile design rules' "$F/ux.md")" 1
eq "surfaces multi: cli overlay once (spec.md)" "$(grep -c '^## Command surface' "$F/spec.md")" 1
assert "surfaces multi: UX default yes with a UI surface" test -f "$F/ux.md"
out=$(kickoff shop shop-front --surfaces web-ui-shop); rc=$?
eq "surfaces web-ui-shop: accepted" "$rc" 0
assert "surfaces web-ui-shop: UX default yes, no overlay sections" bash -c "test -f docs/product/shop/08-shop-front/ux.md && ! grep -rq 'Mobile design rules' docs/product/shop/08-shop-front"
out=$(kickoff shop svc --surfaces service,library,data,infra); rc=$?
eq "surfaces without UI or overlays: exit 0" "$rc" 0
assert "surfaces without UI or overlays: no ux.md" test ! -e docs/product/shop/09-svc/ux.md
out=$(kickoff shop desk --surfaces desktop-ui); rc=$?
assert "surfaces desktop-ui: UX default yes" test -f docs/product/shop/10-desk/ux.md

# An unknown surface is a usage error that lists the kinds and creates nothing.
before=$(snapshot)
out=$(kickoff shop bad --surfaces api,webui 2>&1); rc=$?
eq "surfaces unknown: exit 1" "$rc" 1
assert "surfaces unknown: names the surface" test "$out" != "${out//\'webui\'/}"
assert "surfaces unknown: lists the kinds" test "$out" != "${out//mobile-ui/}" -a "$out" != "${out//infra/}"
eq "surfaces unknown: nothing created" "$(snapshot)" "$before"
kickoff shop bad --surfaces apis >/dev/null 2>&1; eq "surfaces 'apis' is not a surface: exit 1" "$?" 1
kickoff shop bad --surfaces=cli,Web >/dev/null 2>&1; eq "surfaces uppercase: exit 1" "$?" 1
eq "surfaces errors: nothing created" "$(snapshot)" "$before"

# Without --surfaces nothing changes: UX yes, no overlay files or sections, no surfaces= line.
out=$(kickoff shop plain); rc=$?
F=docs/product/shop/11-plain
eq "no surfaces: exit 0" "$rc" 0
assert "no surfaces: UX stays yes" test -f "$F/ux.md" -a ! -e "$F/prototypes"
assert "no surfaces: no overlay files or sections" bash -c "test ! -e '$F/contracts/README.md' && ! grep -rqE 'Mobile design rules|API evidence plan|Eval set|Command surface|Model, prompts' '$F'"
bad=0
for t in "$TPL"/phase/*; do same_as "$F/${t##*/}" "$t" -e 's/Phase <phase>/Feature 11/g' -e 's/<phase>/11/g' -e 's/<Module>/Shop/g' -e 's/<module>/shop/g' || bad=1; done
eq "no surfaces: every doc is its template" "$bad" 0
assert "no surfaces: .plumbline has no surfaces line" bash -c "! grep -q '^surfaces=' '$F/.plumbline'"

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
