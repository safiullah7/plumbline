#!/usr/bin/env bash
# Self-test for the v0.5 security rules in the scripts (dev plan §6.4, §8.1): the
# recorded and required level, the table reader, every gap security_gaps reports
# (with the attack tests run through a stub AC tests command, and once through the
# real node adapter), security-check.sh and signoff-check.sh, the secrets scan, the
# status line, and the ownership guard's locks on Security waived:, Risk accepted:
# and kickoff.sh --set-security. kickoff.sh's own cases are in kickoff-selftest.sh.
# A feature with no security level is checked to behave exactly as before. Run from
# the repo root:
#   bash tests/security-selftest.sh
# Works in bash on macOS and Linux, and in Git Bash on Windows.
set -u
command -v jq >/dev/null 2>&1 || { echo "jq isn't installed or isn't on PATH."; exit 1; }
ROOT="$(cd "$(dirname "${0//\\//}")/.." && pwd)"
G="$ROOT/plugins/plumbline/scripts"
TPL="$ROOT/plugins/plumbline/skills/kickoff/templates"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo" && cd "$T/repo"
export HOME="$T" CLAUDE_PROJECT_DIR="$T/repo"
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_DATA PLUMBLINE_TEST_GLOBS PLUMBLINE_BASE_REF PLUMBLINE_TEST_AC PLUMBLINE_TYPECHECK PLUMBLINE_LINT
source "$ROOT/plugins/plumbline/evals/_fixture/clinic.sh" >/dev/null
set +e   # the fixture sets -e; the checks below expect non-zero exits
source "$G/lib.sh"

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
skip() { echo "skip  $1"; }
assert() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
eq() { # name, got, expected
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (got '$2', expected '$3')"; fi
}
has() { grep -qF -- "$2" <<<"$1"; }   # text, fixed string
US=$'\037'

# --- Fixture: a clinic feature (the legacy phase-01 folder), a profile whose AC tests
# cells are a stub, and a branch to commit secrets on. ---
SEC="$P/security.md"; PLAN="$P/dev-plan.md"
STUB="$T/stub.sh"; export STUB_RULES="$T/stub.rules" STUB_CALLS="$T/stub.calls"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
# stub.sh <label> "<IDs>": a fake AC tests command. One line per ID from $STUB_RULES
# ("<ID> pass|fail|none|missing|generic|genericfail", pass when there is no rule),
# exit 1 unless every ID passes. generic prints the generic adapter's warning and no
# ID line, exit 0; genericfail the same with exit 1.
echo "$1 $2" >> "$STUB_CALLS"
rc=0; g=""
for id in ${2//|/ }; do
  r=$(awk -v id="$id" '$1 == id { print $2 }' "$STUB_RULES" 2>/dev/null); r=${r:-pass}
  case "$r" in
    pass) echo "$id: pass (1)" ;;
    fail) echo "$id: fail"; rc=1 ;;
    missing) echo "$id: missing"; rc=1 ;;
    generic|genericfail) [[ -n "$g" ]] || echo "generic: per-ID presence isn't proven; the command's exit code is the result."; g=1; [[ "$r" == generic ]] || rc=1 ;;
    *) rc=1 ;;
  esac
done
exit $rc
EOF
profile() { # api and web-ui run the stub; cli has no AC tests command, data says none
  project_profile yes none "| api | Node | apps/api/** | | | | bash $STUB api |
| web-ui | React | apps/web/** | | | | bash $STUB web-ui |
| api-attack | Node | apps/attack/** | | | | node --dir apps/attack |
| cli | Rust | cli/** | | | | |
| data | SQL | db/** | | | | none |"
}
profile
git checkout -q -b feat

# A phase whose every other gate is green, so only the security rules can add gaps.
phase_template signoff.md
{ echo "# Phase 01 test plan"; echo; echo "## Traceability"; echo "| AC ID | Test cases | Type | Status |"; echo "| --- | --- | --- | --- |"
  for n in 1 2 3 4 5; do echo "| AC-01-00$n | TC-01-00$n | e2e | Pass |"; done; } > "$P/test-plan.md"
printf '# Phase 01 QA report\n\nVerdict: PASS\n\n## Bugs\n| ID | AC ID | Severity | Status | Summary | Evidence |\n| --- | --- | --- | --- | --- | --- |\n' > "$P/qa-report.md"
sed -i -E '/Phase PR|Merged/! s/^- \[ \]/- [x]/' "$P/signoff.md"

reset() { # level: ready_plan, no security files, .plumbline at that level (none: no file)
  ready_plan
  rm -f "$P/.plumbline" "$SEC"
  : > "$STUB_RULES"; : > "$STUB_CALLS"
  unset PLUMBLINE_TEST_AC PLUMBLINE_BASE_REF
  [[ "$1" == none ]] || printf 'module=clinic\nnumber=01\nprofile=full\nux=yes\nsecurity=%s\n' "$1" > "$P/.plumbline"
}
plan_level() { # token: a "Security level:" line (and its reason) right after Status
  awk -v l="$1" '{ print } /^Status: READY/ && !d { print ""; print "Security level: " l; print "Reason: sessions are touched."; d = 1 }' "$PLAN" > "$T/edit" && mv "$T/edit" "$PLAN"
}
add_plan() { # table rows: appends the lead's ## Attack plan
  { printf '\n## Attack plan\nSignals: tenancy, authorization\nAttack surface: apps/api/rooms/**\nAttack fixtures: apps/api/test/attack/fixtures.js\nSkipped: none\n\n'
    echo '| SEC ID | Surface | Attack | Must happen | Checked |'; echo '| --- | --- | --- | --- | --- |'
    printf '%s\n' "$@"; } >> "$PLAN"
}
raw_plan() { ready_plan; printf '%s\n' "$@" >> "$PLAN"; }   # ready_plan, then these lines as written
write_sec() { # from SEC_IND, SEC_OWN, SEC_FIND, SEC_EXTRA (rows, one per line)
  { echo "# Feature 01 security"; echo; echo "Independent pass: ${SEC_IND:-not started}"; echo
    echo "## Own attacks"; echo "| SEC ID | Surface | Attack | Must happen |"; echo "| --- | --- | --- | --- |"; [[ -n "${SEC_OWN:-}" ]] && printf '%s\n' "$SEC_OWN"
    echo; echo "## Findings"; echo "| # | Severity | Finding | Status | Evidence |"; echo "| --- | --- | --- | --- | --- |"; [[ -n "${SEC_FIND:-}" ]] && printf '%s\n' "$SEC_FIND"
    [[ -n "${SEC_EXTRA:-}" ]] && { echo; printf '%s\n' "$SEC_EXTRA"; }
  } > "$SEC"
}
GREEN=('| SEC-01-001 | api | Clinic B lists clinic A rooms with a valid session | 404, no room in the body | matches |'
       '| SEC-01-002 | web-ui | A forged clinic id in the request | rejected | matches: asserts the status and the body |')
green() { # [attacks|independent]: the feature at that level with every security rule met
  local lvl="${1:-attacks}"
  reset "$lvl"; add_plan "${GREEN[@]}"
  SEC_IND="not needed"; [[ "$lvl" == independent ]] && SEC_IND="complete (round 1)"
  SEC_OWN="" SEC_FIND="" SEC_EXTRA="" write_sec
}
gp() { gaps=$(security_gaps "$@" 2>&1); }
gap() { # name, text a gap must contain
  if grep -qF -- "$2" <<<"$gaps"; then ok "$1"; else fail "$1 (gaps: ${gaps//$'\n'/ | })"; fi
}
nogap() { # name, text no gap may contain
  if grep -qF -- "$2" <<<"$gaps"; then fail "$1 (found '$2' in: ${gaps//$'\n'/ | })"; else ok "$1"; fi
}
clean() { if [[ -z "$gaps" ]]; then ok "$1"; else fail "$1 (gaps: ${gaps//$'\n'/ | })"; fi; }
count() { grep -c . <<<"$1"; }
calls() { paste -sd';' - < "$STUB_CALLS"; }
rows_gaps() { security_rows "$1" | awk -F"$US" '$1 == "gap" { print $2 }'; }
rows_n() { security_rows "$1" | grep -c '^row'; }

# ===== Level: the recorded and the required level =====
reset none
eq "level: no key and no line is none" "$(security_level)" none
eq "level: ...and nothing is required" "$(security_required)" none
reset attacks
eq "level: key attacks" "$(security_level)" attacks
reset independent
eq "level: key independent" "$(security_level)" independent
reset none; plan_level attacks
eq "level: a Security level: line alone counts" "$(security_level)" attacks
reset attacks; plan_level independent
eq "level: the higher of the line and the key wins" "$(security_level)" independent
reset independent; plan_level attacks
eq "level: ...the key may be the higher" "$(security_level)" independent
reset none; plan_level '`attacks`'
eq "level: backticks are stripped" "$(security_level)" attacks
reset none; plan_level '  independent  '
eq "level: spaces are stripped" "$(security_level)" independent
reset none; plan_level none
eq "level: Security level: none is none" "$(security_level)" none
reset none; plan_level 'attacks (the login changes)'
eq "level: a reason on the same line makes the token unknown (fail closed: attacks)" "$(security_level)" attacks
reset none; plan_level high
eq "level: an unknown token fails closed as attacks" "$(security_level)" attacks
reset none; plan_level ''
eq "level: a Security level: line with no token fails closed as attacks" "$(security_level)" attacks
reset none; awk '{ print } /^Status: READY/ { print ""; print "See the Security level: independent line above." }' "$PLAN" > "$T/edit" && mv "$T/edit" "$PLAN"
eq "level: a mention mid-sentence isn't the line" "$(security_level)" none
reset none; awk '{ print } /^Status: READY/ { print ""; print "security level: independent" }' "$PLAN" > "$T/edit" && mv "$T/edit" "$PLAN"
eq "level: the line's name is case-insensitive" "$(security_level)" independent
plan_raw() { awk -v l="$1" '{ print } /^Status: READY/ && !d { print ""; print l; d = 1 }' "$PLAN" > "$T/edit" && mv "$T/edit" "$PLAN"; }
# A formatted declaration the strict parser can't read is an unknown token (attacks, and a gap), never silence.
for l in '**Security level:** independent' '- Security level: independent' '> Security level: attacks' '  Security level: attacks' '* **Security level**: attacks' '_Security level_: none'; do
  reset none; plan_raw "$l"; gp --no-run
  eq "level: \"$l\" is not ignored (counts as attacks)" "$(security_level)" attacks
  gap "...and is a gap that quotes it" "Security level line in dev-plan.md can't be read: $(sed -E 's/^[[:space:]]+//' <<<"$l"); write \`Security level: <attacks|independent>\` on its own line"
done
reset none; plan_raw 'Security Level: attacks'; gp --no-run
eq "level: \"Security Level: attacks\" is read by the strict parser (any case)" "$(security_level)" attacks
nogap "...and is no unreadable line" "can't be read"
reset none; plan_level attacks; plan_raw '- Security level: independent'; gp --no-run
eq "level: a readable line plus a formatted one: the readable one sets the level" "$(security_level)" attacks
gap "...and the formatted one is a gap" "can't be read: - Security level: independent"
reset independent; plan_raw '> Security level: attacks'
eq "level: an unreadable line never lowers the level" "$(security_level)" independent
reset none; plan_raw 'We changed the Security level: see the plan.'; plan_raw 'Raise the security level: later'
eq "level: a mention mid-sentence is not a declaration" "$(security_level)" none
gp --no-run; clean "...and no gap at level none"
reset none; plan_raw 'Security levels: none'
eq "level: \"Security levels:\" is not the name" "$(security_level)" none
reset attacks; sed -i 's/^security=attacks/security = `independent` # raised/' "$P/.plumbline"
eq "level: key with spaces, backticks and a comment" "$(security_level)" independent

# A waiver removes only the part it names, and only when filled in.
W_ATT='Security waived: attacks - the user owns the risk (approved by Sam)'
W_IND='Security waived: independent - low traffic app (approved by Sam)'
req() { SEC_EXTRA="${1:-}" write_sec; security_required; }
reset attacks; SEC_IND="not needed" write_sec
eq "required: attacks, no waiver" "$(security_required)" attacks
reset independent; SEC_IND="not started" write_sec
eq "required: independent includes attacks" "$(security_required)" "attacks independent"
eq "required: attacks waived leaves independent" "$(req "$W_ATT")" independent
eq "required: independent waived leaves attacks" "$(req "$W_IND")" attacks
eq "required: both waived" "$(req "$W_ATT"$'\n'"$W_IND")" none
eq "required: a placeholder waiver waives nothing" "$(req 'Security waived: <attacks|independent> - <reason> (approved by <name>)')" "attacks independent"
eq "required: a waiver without an approver waives nothing" "$(req 'Security waived: attacks - because')" "attacks independent"
eq "required: a waiver with an empty reason waives nothing" "$(req 'Security waived: attacks - (approved by Sam)')" "attacks independent"
eq "required: a waiver of another word waives nothing" "$(req 'Security waived: everything - x (approved by Sam)')" "attacks independent"
eq "required: a waiver mid-sentence waives nothing" "$(req 'We have Security waived: attacks - x (approved by Sam)')" "attacks independent"
eq "required: the waiver is case-insensitive and may use a colon" "$(req 'security WAIVED: Attacks : reason (approved by Sam)')" independent
reset attacks; SEC_EXTRA="$W_ATT" SEC_IND="not needed" write_sec
eq "required: attacks waived at attacks leaves nothing" "$(security_required)" none
reset none; SEC_EXTRA="$W_ATT" write_sec
eq "required: a waiver at level none changes nothing" "$(security_required)" none

# ===== Tables: security_rows reads exactly, and gaps on anything it can't =====
reset attacks; add_plan "${GREEN[@]}"; SEC_IND="not needed" write_sec
eq "rows: the attack plan has two rows" "$(rows_n plan)" 2
eq "rows: ...and no gaps" "$(rows_gaps plan)" ""
eq "rows: a row's cells in order" "$(security_rows plan | sed -n 1p | cut -d"$US" -f2-4)" "SEC-01-001${US}api${US}Clinic B lists clinic A rooms with a valid session"
eq "rows: an empty Checked cell is kept" "$(printf '%s\n' '| SEC-01-009 | api | a | b | |' > "$T/r"; raw_plan '' '## Attack plan' '| SEC ID | Surface | Attack | Must happen | Checked |' '| --- | --- | --- | --- | --- |' "$(cat "$T/r")"; security_rows plan | awk -F"$US" '{ print NF }')" 6
eq "rows: own attacks table of the template is empty and clean" "$(rows_n own)/$(rows_gaps own)" "0/"
eq "rows: findings table of the template is empty and clean" "$(rows_n findings)/$(rows_gaps findings)" "0/"
HDR='| SEC ID | Surface | Attack | Must happen | Checked |'; SEP='| --- | --- | --- | --- | --- |'
raw_plan '' '## Attack plan' 'Signals: x' '' "$HDR" "$SEP" '| SEC-01-001 | api | a | b | matches |' '' '| SEC-01-002 | api | a | b | matches |'
has "$(rows_gaps plan)" "a table row after a blank or text line" && ok "rows: a row after a blank line is a gap" || fail "rows: a row after a blank line is a gap"
eq "rows: ...and the split row isn't read" "$(rows_n plan)" 1
raw_plan '' '## Attack plan' "$HDR" "$SEP" '| SEC-01-001 | api | a | b | matches |' 'Notes after the table.' '' '| SEC-01-002 | api | a | b | matches |'
has "$(rows_gaps plan)" "is split" && ok "rows: a row after a text line is a gap" || fail "rows: a row after a text line is a gap"
raw_plan '' '## Attack plan' "$HDR" "$SEP" '| SEC-01-001 | api | a | b | matches |' '' 'Notes after the table.' ''
eq "rows: text after the table with no more rows is fine" "$(rows_gaps plan)" ""
raw_plan '' '## Attack plan' "$HDR" "$SEP" '| SEC-01-001 | api | a | b | matches |' '' '## Next section' '| SEC-01-002 | api | a | b | matches |'
eq "rows: a table under the next heading isn't the plan's" "$(rows_n plan)/$(rows_gaps plan)" "1/"
raw_plan '' '## Attack plan' "$HDR" "$SEP" '| SEC-01-001 | api | a | b | c | matches |'
has "$(rows_gaps plan)" "6 cells, expected 5" && ok "rows: a | inside a cell is a gap (wrong cell count)" || fail "rows: a | inside a cell is a gap"
eq "rows: ...and the row isn't read" "$(rows_n plan)" 0
raw_plan '' '## Attack plan' "$HDR" "$SEP" '| SEC-01-001 | api | a | b'
has "$(rows_gaps plan)" "must start and end with |" && ok "rows: a row that isn't closed is a gap" || fail "rows: a row that isn't closed is a gap"
raw_plan '' '## Attack plan' '| ID | Surface | Attack | Must happen | Checked |' "$SEP" '| SEC-01-001 | api | a | b | matches |'
has "$(rows_gaps plan)" "must have the header" && ok "rows: a different header is a gap" || fail "rows: a different header is a gap"
eq "rows: ...and its rows aren't read" "$(rows_n plan)" 0
raw_plan '' '## Attack plan' '| SEC ID | Surface | Attack | Must happen |' '| --- | --- | --- | --- |' '| SEC-01-001 | api | a | b |'
has "$(rows_gaps plan)" "must have the header" && ok "rows: a plan table without Checked is a gap" || fail "rows: a plan table without Checked is a gap"
raw_plan '' '## Attack plan' 'Signals: x' 'Skipped: none'
has "$(rows_gaps plan)" "has no table with the header" && ok "rows: a section with no table is a gap" || fail "rows: a section with no table is a gap"
raw_plan '' '## Attack plan' "$HDR" '| SEC-01-001 | api | a | b | matches |'
has "$(rows_gaps plan)" "no separator row" && ok "rows: a table with no separator row is a gap" || fail "rows: a table with no separator row is a gap"
ready_plan
has "$(rows_gaps plan)" 'has no "## Attack plan" section' && ok "rows: a missing section is a gap" || fail "rows: a missing section is a gap"
raw_plan '' '## Attack plan' "$HDR" "$SEP" '| AC-01-001 | api | a | b | matches |'
has "$(rows_gaps plan)" "is not a SEC ID" && ok "rows: an AC ID in the plan is a gap" || fail "rows: an AC ID in the plan is a gap"
raw_plan '' '## Attack plan' "$HDR" "$SEP" '| SEC-01-001 | api | a | b | matches |'
sed -i 's/$/\r/' "$PLAN"
eq "rows: a CRLF file reads the same" "$(rows_n plan)/$(rows_gaps plan)" "1/"
raw_plan '' '## Attack plan' "$HDR" "$SEP" '|SEC-01-001|api|a|b|matches|' '|   SEC-01-002   |  api  |  a  |  b  |  matches  |'
eq "rows: cells are trimmed, spaces around | optional" "$(rows_n plan)/$(rows_gaps plan)" "2/"
raw_plan '' '## attack plan' "$HDR" "$SEP" '| SEC-01-001 | api | a | b | matches |'
has "$(rows_gaps plan)" 'has no "## Attack plan" section' && ok "rows: the heading must be exact (## Attack plan)" || fail "rows: the heading must be exact"

# security.md: Own attacks and Findings.
SEC_IND="not started" SEC_OWN="" SEC_FIND='| 1 | high | Tenant leak | open | a |' write_sec
eq "rows: one finding, cells in order" "$(security_rows findings | cut -d"$US" -f2-5)" "1${US}high${US}Tenant leak${US}open"
SEC_FIND='| 1 | urgent | Tenant leak | open | a |' write_sec
has "$(rows_gaps findings)" 'severity "urgent"' && ok "rows: an unknown severity is a gap" || fail "rows: an unknown severity is a gap"
eq "rows: ...and the row isn't read" "$(rows_n findings)" 0
SEC_FIND='| 1 | HIGH | Tenant leak | OPEN | a |' write_sec
eq "rows: severity in any case is read" "$(rows_n findings)/$(rows_gaps findings)" "1/"
SEC_FIND='| 1 | high | Tenant leak | open | a |'$'\n''| 2 | low | Typo | open | b | extra |' write_sec
has "$(rows_gaps findings)" "6 cells, expected 5" && ok "rows: a finding with a | in a cell is a gap" || fail "rows: a finding with a | in a cell is a gap"
eq "rows: ...the good row is still read" "$(rows_n findings)" 1
SEC_FIND='| 1 | high | Tenant leak | open | a |'$'\n\n''| 2 | low | Typo | open | b |' write_sec
has "$(rows_gaps findings)" "is split" && ok "rows: a finding after a blank line is a gap" || fail "rows: a finding after a blank line is a gap"
SEC_OWN='| SEC-01-003 | api | own | blocked |'$'\n''| SEC-01-004 | api | own | blocked | oops |' write_sec
has "$(rows_gaps own)" "5 cells, expected 4" && ok "rows: an own attack with the wrong cell count is a gap" || fail "rows: an own attack with the wrong cell count is a gap"
SEC_OWN='| SEC-01-003 | api | own | blocked |' SEC_FIND="" write_sec
eq "rows: an own attack is read" "$(security_rows own | cut -d"$US" -f2-3)" "SEC-01-003${US}api"
grep -v '^## Findings' "$SEC" | grep -v '^| # ' | grep -v '^| --- | --- | --- | --- | --- |' > "$T/edit" && cp "$T/edit" "$SEC"
has "$(rows_gaps findings)" 'has no "## Findings" section' && ok "rows: a missing ## Findings is a gap" || fail "rows: a missing ## Findings is a gap"
sed -i 's/^## Own attacks/## Attacks of our own/' "$SEC"
has "$(rows_gaps own)" 'has no "## Own attacks" section' && ok "rows: a renamed ## Own attacks is a gap" || fail "rows: a renamed ## Own attacks is a gap"
rm -f "$SEC"
security_rows own >/dev/null; eq "rows: no security.md returns 1" "$?" 1

# ### and deeper headings stay inside the section; each table under them is read the same way.
FH='| # | Severity | Finding | Status | Evidence |'; FS='| --- | --- | --- | --- | --- |'
sub_find() { SEC_IND="not started" SEC_OWN="" SEC_FIND="$(printf '%s\n' '| 1 | low | a | open | b |' '' "$@")" write_sec; }
sub_find '### Round 2' '' "$FH" "$FS" '| 2 | critical | Token leak | open | c |'
eq "rows: a table under a ### heading in Findings is read" "$(rows_n findings)/$(rows_gaps findings)" "2/"
sub_find '#### Round 2' "$FH" "$FS" '| 2 | critical | Token leak | open | c |'
eq "rows: ...a #### heading too" "$(rows_n findings)/$(rows_gaps findings)" "2/"
sub_find '### Round 2' '' 'Nothing found this round.'
eq "rows: a ### heading with no table is fine" "$(rows_n findings)/$(rows_gaps findings)" "1/"
sub_find '### Notes' '| a | b |' '| c | d |'
has "$(rows_gaps findings)" "must have the header" && ok "rows: a | line under ### that is not a table is a gap" || fail "rows: a | line under ### that is not a table is a gap ($(rows_gaps findings))"
sub_find '### Round 2' "$FH" "$FS" '| 2 | urgent | x | open | c |' '| 3 | low | y | open | c | extra |'
has "$(rows_gaps findings)" 'severity "urgent"' && has "$(rows_gaps findings)" "6 cells, expected 5" && ok "rows: ...the same row rules apply there" || fail "rows: the same row rules under ### ($(rows_gaps findings))"
sub_find 'Round 2:' "$FH" "$FS" '| 2 | high | x | open | c |'
eq "rows: another exact-header table after a text line is read" "$(rows_n findings)/$(rows_gaps findings)" "2/"
sub_find '### Round 2' '| # | Severity |' '| --- | --- |' '| 2 | high |'
has "$(rows_gaps findings)" "must have the header" && ok "rows: a table with another header under ### is a gap" || fail "rows: another header under ### ($(rows_gaps findings))"
sub_find '## Appendix' "$FH" "$FS" '| 2 | high | not read | open | c |'
eq "rows: a ## heading still ends the section" "$(rows_n findings)/$(rows_gaps findings)" "1/"
sub_find '# Appendix' "$FH" "$FS" '| 2 | high | not read | open | c |'
eq "rows: ...and a # heading" "$(rows_n findings)/$(rows_gaps findings)" "1/"
green attacks; SEC_IND="not needed" SEC_OWN="" SEC_FIND="$(printf '%s\n' '| 1 | low | a | open | b |' '' '### Round 2' "$FH" "$FS" '| 2 | critical | Token leak | open | c |')" write_sec; gp --no-run
gap "rows: an open critical finding in a ### table is a gap" "open critical finding #2: Token leak"
green attacks; ready_plan; printf '\n## Attack plan\nSignals: x\n\n### Round 1\n\n%s\n%s\n| SEC-01-001 | api | a | b | matches |\n\n### Round 2\n\n%s\n%s\n| SEC-01-002 | web-ui | a | b | matches |\n' "$HDR" "$SEP" "$HDR" "$SEP" >> "$PLAN"
eq "rows: the attack plan reads a table under each ### heading" "$(rows_n plan)/$(rows_gaps plan)" "2/"

# ===== security_gaps: level none runs nothing and adds nothing =====
with_plan() { # rows: a feature at attacks with this attack plan and a clean security.md
  reset attacks; add_plan "$@"; SEC_IND="not needed" SEC_OWN="" SEC_FIND="" SEC_EXTRA="" write_sec
}
reset none; add_plan "${GREEN[@]}"   # a plan and no security.md: not looked at at none
gp
clean "none: no gap"
eq "none: no test ran" "$(calls)" ""

# ===== security_gaps: green features =====
green attacks
gp
clean "attacks: a green feature has no gap"
eq "attacks: each surface ran once with its SEC IDs" "$(calls)" "api SEC-01-001;web-ui SEC-01-002"
: > "$STUB_CALLS"; echo "SEC-01-001 fail" > "$STUB_RULES"
gp --no-run
clean "--no-run: skips the run (a failing test isn't seen)"
eq "--no-run: ...and no test ran" "$(calls)" ""
: > "$STUB_RULES"
green independent
gp
clean "independent: a green feature has no gap"

# ===== The recorded level =====
reset attacks; sed -i 's/^security=attacks/security=maybe/' "$P/.plumbline"; plan_level strict; rm -f "$SEC"; gp --no-run
gap "unknown token in .plumbline" 'unknown security level "maybe" in .plumbline'
gap "unknown token on the Security level: line" 'unknown security level "strict" on the Security level: line'
gap "missing security.md (the unknown tokens count as attacks)" "security.md is missing; run kickoff.sh --set-security attacks"
green attacks; plan_level independent; gp --no-run
gap "raise not recorded" "raise not recorded: dev-plan.md says Security level: independent but .plumbline says attacks; run kickoff.sh --set-security independent"
gap "...and the raised level's independent pass is required" "the independent pass is not needed, not complete"
green attacks; rm -f "$P/.plumbline"; plan_level attacks; gp --no-run
gap "a raise with no key at all is not recorded" "raise not recorded: dev-plan.md says Security level: attacks but .plumbline says nothing"
green attacks; plan_level attacks; gp --no-run
clean "a plan line equal to the key is no gap"

# ===== The documents =====
reset attacks; printf '# Feature 01 security\n\nIndependent pass: not needed\n' > "$SEC"; gp --no-run
gap "missing ## Own attacks heading" 'has no "## Own attacks" section'
gap "missing ## Findings heading" 'has no "## Findings" section'
gap "missing attack plan" 'dev-plan.md has no "## Attack plan" section'
nogap "...once, not also as an empty plan" "has no rows"
with_plan; gp --no-run
gap "empty attack plan" "the attack plan has no rows"
with_plan '| SEC-01-001 | api | a | b | |' '| SEC-01-002 | web-ui | a | b | mismatch: asserts only the status |' '| SEC-01-003 | api | a | b | Matches |' \
  '| SEC-01-004 | api | a | b | matches with a note |' '| SEC-01-005 | | a | b | matches |'
gp --no-run
gap "empty Checked" "attack SEC-01-001: Checked is empty, not matches"
gap "mismatch in Checked" 'attack SEC-01-002: Checked is "mismatch: asserts only the status", not matches'
nogap "Checked starting matches, in any case, is fine" "attack SEC-01-003"
nogap "...with a note after it" "attack SEC-01-004"
gap "a plan row with no Surface" "attack SEC-01-005 has no Surface"
with_plan '| SEC-01-001 | api | a | b | matches |' '' '| SEC-01-002 | api | a | b | matches |'; gp --no-run
gap "a split attack plan table" "is split"

# ===== The run: results per ID, surfaces, and a run that can't start =====
with_plan '| SEC-01-001 | api | a | b | matches |' '| SEC-01-002 | api | a | b | matches |' '| SEC-01-003 | api | a | b | matches |' \
  '| SEC-01-004 | web-ui | a | b | matches |' '| SEC-01-005 | mobile-ui | a | b | matches |' '| SEC-01-006 | cli | a | b | matches |' \
  '| SEC-01-007 | data | a | b | matches |' '| SEC-01-008 | API | a | b | matches |'
printf 'SEC-01-002 fail\nSEC-01-003 none\n' > "$STUB_RULES"; gp
gap "a failing SEC test is a gap with the adapter's line" "attack test did not pass on api: SEC-01-002: fail"
gap "a SEC ID the run prints nothing for" "attack test SEC-01-003 gave no result on api"
nogap "a passing SEC test is no gap (api)" "SEC-01-001: "
nogap "...nor on web-ui" "SEC-01-004: "
eq "IDs of one surface run together, once" "$(calls)" "api SEC-01-001|SEC-01-002|SEC-01-003;web-ui SEC-01-004"
gap "a surface the profile doesn't list" "surface \"mobile-ui\" (for SEC-01-005) isn't in docs/product/project.md's Surfaces table; the profile lists: api, web-ui, api-attack, cli, data"
gap "surface names are exact (API isn't api)" 'surface "API" (for SEC-01-008)'
gap "a blank AC tests cell" "attack tests for SEC-01-006 on cli gave no results"
gap "...with ac-check's message" "no command for surface cli"
gap "an AC tests cell of none" "attack tests for SEC-01-007 on data gave no results"
gap "...with ac-check's message" "no AC test command configured"
with_plan '| SEC-01-001 | web-ui | a | b | matches |'; printf 'SEC-01-001 none\n' > "$STUB_RULES"; gp
gap "a surface whose run prints no line at all" "attack tests for SEC-01-001 on web-ui gave no results (ac-check exit 1)"
with_plan '| SEC-01-001 | api | a | b | matches |'; : > "$STUB_RULES"; export PLUMBLINE_TEST_AC='this-command-does-not-exist-xyz'; gp
gap "a run that can't start" "attack tests for SEC-01-001 on api gave no results (ac-check exit"
unset PLUMBLINE_TEST_AC
green attacks; export PLUMBLINE_TEST_AC="bash $STUB env" PLUMBLINE_TYPECHECK="exit 7" PLUMBLINE_LINT="exit 7"; gp
clean "PLUMBLINE_TEST_AC overrides the cells, and typecheck and lint are skipped by the run"
eq "...one run per surface" "$(calls)" "env SEC-01-001;env SEC-01-002"
unset PLUMBLINE_TEST_AC PLUMBLINE_TYPECHECK PLUMBLINE_LINT
green attacks; mv docs/product/project.md "$T/project.md"; export PLUMBLINE_TEST_AC="bash $STUB legacy"; gp
clean "no profile: one run, no surface"
eq "...for every ID" "$(calls)" "legacy SEC-01-001|SEC-01-002"
unset PLUMBLINE_TEST_AC; mv "$T/project.md" docs/product/project.md

# Own attacks run like the plan's.
green attacks; SEC_IND="not needed" SEC_OWN='| SEC-01-003 | api | A replayed token | 401 |'$'\n''| SEC-01-004 | | No surface | x |' write_sec
printf 'SEC-01-003 fail\n' > "$STUB_RULES"; gp
gap "an own attack that fails" "attack test did not pass on api: SEC-01-003: fail"
gap "an own attack with no Surface" "own attack SEC-01-004 has no Surface"
eq "own attacks run with the plan's IDs for their surface" "$(calls)" "api SEC-01-001|SEC-01-003;web-ui SEC-01-002"
: > "$STUB_RULES"

# ===== Findings =====
FIND=(
  '| 1 | high | open-high-leak | open | x |'
  '| 2 | Critical | open-critical-token | open | x |'
  '| 3 | high | fixed-not-verified | fixed | x |'
  '| 4 | high | verified-is-closed | verified | x |'
  '| 5 | medium | medium-open | open | x |'
  '| 6 | low | low-open | open | x |'
  '| 7 | high | accepted-exact | open | x |'
  '| 8 | HIGH | accepted-folded text | OPEN | x |'
  '| 9 | high | rewritten-after-accepting | open | x |'
  '| 10 | critical | severity-changed | open | x |'
  '| 11 | high | other-number | open | x |'
  '| 12 | high | no-reason | open | x |'
  '| 13 | high | no-approver | open | x |'
  '| 14 | high | placeholder-only | open | x |'
  '| 15 | high | longer-text | open | x |'
  '| #16 | high | hash-in-number-cell | open | x |')
ACC=(
  'Risk accepted: #7 high accepted-exact - demo data only (approved by Sam)'
  "risk ACCEPTED:   #8  High  ACCEPTED-folded   text : demo data only (approved by Sam)"
  'Risk accepted: #9 high the original text - demo data only (approved by Sam)'
  'Risk accepted: #10 high severity-changed - demo data only (approved by Sam)'
  'Risk accepted: #99 high other-number - demo data only (approved by Sam)'
  'Risk accepted: #12 high no-reason (approved by Sam)'
  'Risk accepted: #13 high no-approver - demo data only'
  'Risk accepted: #<n> <severity> <the finding text exactly as in the row> - <reason> (approved by <name>)'
  'Risk accepted: #15 high longer-text and more words - demo data only (approved by Sam)'
  'Risk accepted: #16 high hash-in-number-cell - demo data only (approved by Sam)')
reset attacks; add_plan "${GREEN[@]}"; SEC_IND="not needed" SEC_FIND="$(printf '%s\n' "${FIND[@]}")" SEC_EXTRA="$(printf '%s\n' "${ACC[@]}")" write_sec
gp --no-run
for n in 1 2 3 9 10 11 12 13 14 15; do gap "finding #$n stays open" "finding #$n:"; done
for n in 4 5 6 7 8 16; do nogap "finding #$n is closed, minor or accepted" "finding #$n:"; done
eq "only those ten findings are gaps" "$(count "$gaps")" 10
gap "an open high finding names its text" "open high finding #1: open-high-leak (security.md)"
gap "...and an open critical one" "open critical finding #2: open-critical-token"

# A finding's text may hold <id>; only the reason and the approval are tested for <placeholders>.
ANGLE="GET /orders/<id> returns another tenant's order"
acc3() { reset attacks; add_plan "${GREEN[@]}"; SEC_IND="not needed" SEC_FIND="| 1 | high | $ANGLE | open | x |" SEC_EXTRA="$1" write_sec; gp --no-run; }
acc3 "Risk accepted: #1 high $ANGLE - demo data only (approved by Sam)"
clean "accepted: a finding text holding <id> can be accepted"
acc3 "risk ACCEPTED:  #1 HIGH  get /orders/<ID>  returns another tenant's order : demo data (approved by Sam)"
clean "...whitespace and case folded, as for any text"
acc3 "Risk accepted: #1 high $ANGLE - <reason> (approved by Sam)"
gap "accepted: a <placeholder> reason after it still approves nothing" "open high finding #1"
acc3 "Risk accepted: #1 high $ANGLE - demo data only (approved by <name>)"
gap "...nor a <name> approver" "open high finding #1"
acc3 "Risk accepted: #1 high $ANGLE and more - demo data only (approved by Sam)"
gap "...nor a longer finding text" "open high finding #1"
acc3 "Risk accepted: #1 high GET /orders/<id> returns another tenant's - demo data only (approved by Sam)"
gap "...nor a shorter one" "open high finding #1"
SEC_EXTRA='Risk accepted: secret apps/<x>/a.js - a published example key (approved by Sam)' write_sec
assert "accepted: a secret path holding < is matched" security_accepted "secret apps/<x>/a.js" 0
SEC_EXTRA='Risk accepted: secret apps/<x>/a.js - <reason> (approved by Sam)' write_sec
assert "...but not with a <placeholder> reason" test "$(security_accepted "secret apps/<x>/a.js" 0; echo $?)" = 1

# ===== Independent pass =====
green independent; SEC_IND="not started" write_sec; gp --no-run
gap "independent: pass not started" "the independent pass is not started, not complete"
green independent; SEC_IND="complete" write_sec; gp --no-run
gap "independent: complete without a round is not enough" "not complete"
green independent; SEC_IND="complete (round 2)" write_sec; gp --no-run
clean "independent: complete (round 2)"
green independent; SEC_IND="complete (round 12)" write_sec; gp --no-run
clean "independent: complete (round 12)"
for v in "complete (round n)" "complete (round <n>)" "complete (done)" "complete ()" "complete (round )" "complete (round 1) and more" "complete (rounds 1)"; do
  green independent; SEC_IND="$v" write_sec; gp --no-run
  gap "independent: \"$v\" is not complete" "not complete"
done
green independent; sed -i '/^Independent pass:/d' "$SEC"; gp --no-run
gap "independent: no Independent pass: line" "the independent pass is missing, not complete"
green attacks; SEC_IND="not started" write_sec; gp --no-run
clean "attacks: the independent pass isn't required"

# ===== Waivers =====
green independent; SEC_IND="not started" SEC_EXTRA="$W_IND" write_sec; gp --no-run
clean "independent waived: the pass isn't required"
reset independent; add_plan '| SEC-01-001 | api | a | b | |'; SEC_IND="not started" SEC_EXTRA="$W_IND" write_sec; gp --no-run
gap "independent waived doesn't waive attacks" "attack SEC-01-001: Checked is empty"
reset independent; SEC_IND="not started" SEC_EXTRA="$W_ATT" write_sec; gp --no-run
gap "attacks waived doesn't waive independent" "the independent pass is not started"
nogap "...and the plan's checks are off" "Attack plan"
reset attacks; SEC_EXTRA="$W_ATT" SEC_IND="not needed" write_sec; : > "$STUB_CALLS"; gp
clean "attacks waived: no plan needed, nothing run"
eq "...no test ran" "$(calls)" ""
reset attacks; SEC_EXTRA='Security waived: attacks - x' SEC_IND="not needed" write_sec; gp --no-run
gap "an unapproved waiver waives nothing" 'has no "## Attack plan" section'
reset independent; SEC_EXTRA="$W_ATT" SEC_IND="complete (round 1)" SEC_OWN='| SEC-01-003 | api | own | blocked |' write_sec
: > "$STUB_CALLS"; printf 'SEC-01-003 fail\n' > "$STUB_RULES"; gp
gap "attacks waived at independent: the attacker's own attacks still run" "attack test did not pass on api: SEC-01-003: fail"
eq "...but not the plan's" "$(calls)" "api SEC-01-003"
: > "$STUB_RULES"

# Own attacks and findings: the attacker writes each own attack to fail while its hole is
# open, so a failing one is not a gap when a finding names it and covers it.
OWN3='| SEC-01-003 | api | A replayed token | 401 |'
own_find() { # findings rows (one per line) [acceptance lines]: one failing own attack, SEC-01-003
  green attacks; SEC_IND="not needed" SEC_OWN="$OWN3" SEC_FIND="$1" SEC_EXTRA="${2:-}" write_sec
  printf 'SEC-01-003 fail\n' > "$STUB_RULES"; gp
}
own_find '| 1 | medium | Replay accepted | open | SEC-01-003 fails today |'
clean "own vs finding: a medium finding naming the attack in Evidence covers its failure"
own_find '| 1 | low | SEC-01-003: the replayed token is accepted | open | see tests |'
clean "...a low one, naming it in the Finding cell"
own_find '| 1 | high | Replay accepted | open | SEC-01-003 |'
gap "own vs finding: an open high finding is its own gap" "open high finding #1: Replay accepted"
nogap "...and the failing test is not reported again" "attack test did not pass"
eq "...one gap in all" "$(count "$gaps")" 1
own_find '| 1 | critical | Replay accepted | open | SEC-01-003 |' 'Risk accepted: #1 critical Replay accepted - demo data (approved by Sam)'
clean "own vs finding: an accepted critical finding covers its failure"
own_find '| 1 | high | Replay accepted | open | SEC-01-003 |' 'Risk accepted: #1 high Replay accepted - <reason> (approved by Sam)'
eq "...an invalid acceptance doesn't: only the finding is a gap" "$(count "$gaps")/$(grep -c 'open high finding #1' <<<"$gaps")" "1/1"
own_find ''
gap "own vs finding: a failing own attack no finding names is a gap" "attack test did not pass on api: SEC-01-003: fail"
gap "...that says to record a finding or fix it" "record a finding in security.md that names SEC-01-003, or fix it"
own_find '| 1 | medium | Something else | open | SEC-01-004 |'
gap "own vs finding: a finding naming another ID covers nothing" "attack test did not pass on api: SEC-01-003: fail"
own_find '| 1 | medium | Replay accepted | verified | SEC-01-003 |'
gap "own vs finding: a verified finding doesn't cover a failing test" "attack test did not pass on api: SEC-01-003: fail"
own_find '| 1 | medium | Replay accepted | fixed | SEC-01-003 |'$'\n''| 2 | low | Also replay | open | SEC-01-003 |'
clean "own vs finding: any covering finding is enough"
printf 'SEC-01-003 missing\n' > "$STUB_RULES"; gp
gap "own vs finding: a missing test is not a failing one (a finding doesn't cover it)" "attack test did not pass on api: SEC-01-003: missing"
nogap "...and gets no record-a-finding hint" "record a finding"
green attacks; SEC_IND="not needed" SEC_OWN="$OWN3"$'\n''| SEC-01-004 | api | A second one | 403 |' SEC_FIND='| 1 | medium | Replay | open | SEC-01-003 |' write_sec
printf 'SEC-01-003 fail\nSEC-01-004 fail\n' > "$STUB_RULES"; gp
gap "own vs finding: only the named attack is covered" "SEC-01-004: fail"
nogap "...not the other" "SEC-01-003"
# The attack plan's IDs stay strict: only an attacks waiver removes them.
green attacks; SEC_IND="not needed" SEC_OWN="$OWN3" SEC_FIND='| 1 | medium | Plan attack fails | open | SEC-01-001 |' write_sec
printf 'SEC-01-001 fail\n' > "$STUB_RULES"; gp
gap "own vs finding: a failing plan attack is a gap whatever a finding says" "attack test did not pass on api: SEC-01-001: fail"
nogap "...with no own-attack hint" "record a finding"
: > "$STUB_RULES"

# The generic adapter prints no per-ID lines: a run that exits 0 with its warning passes
# every ID of the run by exit status; a non-zero exit stays a gap.
green attacks; printf 'SEC-01-001 generic\n' > "$STUB_RULES"; gp
clean "generic: exit 0 with only the generic: warning passes the IDs"
with_plan '| SEC-01-001 | api | a | b | matches |' '| SEC-01-002 | api | a | b | matches |'
printf 'SEC-01-001 generic\nSEC-01-002 generic\n' > "$STUB_RULES"; gp
clean "generic: ...every ID of the run"
printf 'SEC-01-001 genericfail\nSEC-01-002 genericfail\n' > "$STUB_RULES"; gp
gap "generic: a non-zero exit with no ID lines is still a gap" "attack tests for SEC-01-001 SEC-01-002 on api gave no results (ac-check exit 1)"
printf 'SEC-01-001 generic\nSEC-01-002 fail\n' > "$STUB_RULES"; gp
gap "generic: a run that prints an ID line is judged per ID" "attack test did not pass on api: SEC-01-002: fail"
gap "...and an ID with no line is not passed by exit status there" "attack test SEC-01-001 gave no result on api"
: > "$STUB_RULES"

# ===== Secrets scan =====
FAKE_AWS="AKIA""IOSFODNN7EXAMPLE"; FAKE_SK="sk_""live_abcdefghij1234"; FAKE_GH="ghp_""$(printf 'a%.0s' $(seq 1 36))"
FAKE_SLACK="xoxb-""1234567890-abcdefghij"; FAKE_PEM="-----BEGIN RSA PRIV""ATE KEY-----"
commit_add() { # path, lines...: commit a new file on the branch
  mkdir -p "$(dirname "$1")"; printf '%s\n' "${@:2}" > "$1"; git add -- "$1"; git commit -qm "add $1"
}
to_base() { git reset -q --mixed main; git clean -fdq -- "$@"; }
scan() { scan_out=$(secrets_scan); scan_rc=$?; }
scan; eq "secrets: a branch with no additions is clean" "$scan_out/$scan_rc" "/0"
commit_add apps/api/config.js '// config' "const k = \"$FAKE_AWS\";"; scan
eq "secrets: AKIA key, with its line" "$scan_out" "apps/api/config.js:2"; to_base apps/api/config.js
commit_add apps/api/pay.js "const s = '$FAKE_SK';"; scan
eq "secrets: sk_live_ key" "$scan_out" "apps/api/pay.js:1"; to_base apps/api/pay.js
commit_add apps/api/gh.js 'a' 'b' "token=$FAKE_GH"; scan
eq "secrets: ghp_ token" "$scan_out" "apps/api/gh.js:3"; to_base apps/api/gh.js
commit_add apps/api/slack.js "const t = '$FAKE_SLACK';"; scan
eq "secrets: xoxb- token" "$scan_out" "apps/api/slack.js:1"; to_base apps/api/slack.js
commit_add deploy/key.pem "$FAKE_PEM" 'MIIB' '-----END RSA PRIVATE KEY-----'; scan
eq "secrets: a private key block (one hit, on its first line)" "$scan_out" "deploy/key.pem:1"; to_base deploy
commit_add deploy/key2.pem '-----BEGIN PRIVATE KEY-----' 'MIIB'; scan
eq "secrets: ...also without an algorithm" "$scan_out" "deploy/key2.pem:1"; to_base deploy
commit_add .env 'DB_URL=postgres://localhost/clinic'; scan
eq "secrets: an added .env file" "$scan_out" ".env:1"; to_base .env
commit_add apps/api/.env.production 'A=1'; scan
eq "secrets: an added .env.production, in a subfolder" "$scan_out" "apps/api/.env.production:1"; to_base apps/api/.env.production
commit_add apps/api/.env.example 'A=1' 'B=2'; commit_add apps/api/.env.sample 'A=1'; commit_add apps/api/.env.template 'A=1'; commit_add apps/api/.envrc 'use node'; scan
eq "secrets: .env.example, .env.sample, .env.template and .envrc are fine" "$scan_out" ""; to_base apps/api
commit_add apps/api/stripe.js "const pk = 'pk_""live_abcdefghij1234';" '// the password = hunter2 is read from the vault' 'password = "x"' 'const note = "set the password in settings";'; scan
eq "secrets: pk_live_ keys and the word password never hit" "$scan_out" ""; to_base apps/api
commit_add apps/api/multi.js "a = '$FAKE_AWS'" 'ok' "b = '$FAKE_SK'"; scan
eq "secrets: two hits, one per line, in order" "$scan_out" $'apps/api/multi.js:1\napps/api/multi.js:3'; to_base apps/api
# A removed line never hits: the secret is in the base commit and the branch deletes it.
commit_add apps/api/old.js "const k = '$FAKE_AWS';" 'keep'; c1=$(git rev-parse HEAD)
printf 'keep\n' > apps/api/old.js; git add apps/api/old.js; git commit -qm "drop the key"
PLUMBLINE_BASE_REF=$c1 scan
eq "secrets: a removed line doesn't hit" "$scan_out" ""
scan
eq "secrets: ...and a secret added and removed on the branch is gone from the diff" "$scan_out" ""
to_base apps/api
commit_add apps/api/crlf.js "x = '$FAKE_AWS'"$'\r'; scan
eq "secrets: a CRLF line hits" "$scan_out" "apps/api/crlf.js:1"; to_base apps/api
commit_add "apps/api/my file.js" "x = '$FAKE_AWS'"; scan
eq "secrets: a path with a space" "$scan_out" "apps/api/my file.js:1"; to_base apps/api
# The base: PLUMBLINE_BASE_REF, origin/HEAD, main, master; none is a gap.
commit_add apps/api/c.js "k = '$FAKE_AWS'"; c2=$(git rev-parse HEAD); commit_add apps/api/d.js 'fine'
PLUMBLINE_BASE_REF=$c2 scan
eq "secrets base: PLUMBLINE_BASE_REF is the base" "$scan_out" ""
PLUMBLINE_BASE_REF=no-such-ref scan
eq "secrets base: a PLUMBLINE_BASE_REF that doesn't exist can't scan (rc 2)" "$scan_out/$scan_rc" "/2"
scan; eq "secrets base: main is the default" "$scan_out" "apps/api/c.js:1"
git branch -m main master; scan
eq "secrets base: master when there is no main" "$scan_out" "apps/api/c.js:1"
git branch -m master trunk
scan; eq "secrets base: no main, master or origin/HEAD: rc 2, nothing printed" "$scan_out/$scan_rc" "/2"
git update-ref refs/remotes/origin/trunk "$(git merge-base HEAD trunk)"; git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
scan; eq "secrets base: origin/HEAD's target" "$scan_out" "apps/api/c.js:1"
git symbolic-ref --delete refs/remotes/origin/HEAD; git update-ref -d refs/remotes/origin/trunk
git branch -m trunk main
to_base apps/api

# The gap: several committed secrets, one accepted per rule.
for f in a b c d e f g; do commit_add "apps/api/$f.js" "k = '$FAKE_AWS'"; done
SEC_ACC=(
  'Risk accepted: secret apps/api/a.js - a published example key (approved by Sam)'
  'Risk accepted: secret apps/api/other.js - x (approved by Sam)'
  'Risk accepted: secret apps/api/b.js.bak - x (approved by Sam)'
  'Risk accepted: secret apps/api/c.js (approved by Sam)'
  'Risk accepted: secret apps/api/d.js - x'
  'Risk accepted: #1 high apps/api/e.js - x (approved by Sam)'
  'Risk accepted: secret apps/api/f.js-old - x (approved by Sam)')
green attacks; SEC_IND="not needed" SEC_EXTRA="$(printf '%s\n' "${SEC_ACC[@]}" "$W_ATT")" write_sec; gp --no-run
gap "gap: a secret-looking addition" "secret-looking apps/api/g.js:1"
gap "...naming the line that accepts it" "Risk accepted: secret apps/api/g.js"
nogap "Risk accepted: secret covers its path" "secret-looking apps/api/a.js"
for f in b c d e f g; do gap "...but not $f.js (another path, a longer path, no reason, no approver, a finding line, a dash-continued path, none)" "secret-looking apps/api/$f.js:1"; done
eq "the scan still runs with attacks waived and --no-run: six gaps" "$(count "$gaps")" 6
to_base apps/api
green attacks; git checkout -q main; gp --no-run; git checkout -q feat
clean "secrets: on the base branch itself there is nothing to find"
green attacks; git branch -m main gone; gp --no-run
gap "gap: no base branch makes the scan a gap (fail closed)" "secrets scan could not run: no base branch"
reset none; gp --no-run
clean "...but at level none the scan isn't looked at"
git branch -m gone main

# ===== security-check.sh and signoff-check.sh =====
sc() { out=$(bash "$G/security-check.sh" "$@" 2>&1); rc=$?; }
green attacks; : > "$STUB_CALLS"; sc
eq "security-check: a green feature exits 0" "$rc" 0
has "$out" "Recorded level: attacks (.plumbline: attacks, dev-plan.md: none)" && ok "security-check: reports the recorded level and both sources" || fail "security-check: recorded level ($out)"
has "$out" "Required: attacks" && ok "security-check: reports the required level" || fail "security-check: required level"
has "$out" "SEC-01-002 [web-ui] Checked: matches: asserts the status and the body" && ok "security-check: lists plan rows with Checked" || fail "security-check: plan rows"
has "$out" "SEC-01-001 [api]: pass (1)" && ok "security-check: shows each SEC result" || fail "security-check: results ($out)"
has "$out" "Secrets scan: clean" && ok "security-check: reports the secrets scan" || fail "security-check: secrets"
has "$out" "Open critical and high findings: none" && ok "security-check: reports open findings" || fail "security-check: findings"
has "$out" "Independent pass: not needed" && ok "security-check: reports the independent pass" || fail "security-check: independent"
has "$out" "Security check: no gaps." && ok "security-check: says no gaps" || fail "security-check: no gaps"
bash "$G/security-check.sh" --bogus >/dev/null 2>&1; eq "security-check: bad usage exits 2" "$?" 2
green attacks; : > "$STUB_CALLS"; printf 'SEC-01-002 fail\n' > "$STUB_RULES"; SEC_IND="not needed" SEC_FIND='| 1 | high | Tenant leak | open | x |' write_sec; sc --no-run
eq "security-check --no-run: runs nothing" "$(calls)" ""
has "$out" "not run (--no-run)" && ok "security-check --no-run: says the tests weren't run" || fail "security-check --no-run: says so"
has "$out" "#1 high (open): Tenant leak" && ok "security-check: lists open critical and high findings" || fail "security-check: open findings ($out)"
eq "security-check: ...and exits 1" "$rc" 1
assert "security-check --no-run: the failing test isn't seen" test -z "$(grep "did not pass" <<<"$out")"
sc
has "$out" "SEC-01-002 [web-ui]: fail" && ok "security-check: a failing attack's result is shown" || fail "security-check: shows fail ($out)"
has "$out" "Security check: 2 gap(s):" && ok "security-check: gaps are counted" || fail "security-check: counts gaps ($out)"
has "$out" "- attack test did not pass on web-ui: SEC-01-002: fail" && ok "security-check: ...and listed" || fail "security-check: lists gaps"
# Notes are not gaps: a failing own attack that a finding covers, a generic runner's exit status.
green attacks; SEC_IND="not needed" SEC_OWN="$OWN3" SEC_FIND='| 1 | medium | Replay accepted | open | SEC-01-003 |' write_sec
printf 'SEC-01-003 fail\n' > "$STUB_RULES"; sc
eq "security-check: a failing own attack covered by a medium finding exits 0" "$rc" 0
has "$out" "SEC-01-003 [api]: fail" && has "$out" "Notes:" && has "$out" "SEC-01-003 fails: finding #1 (medium)" && ok "security-check: ...with the failure and a note" || fail "security-check: own attack note ($out)"
has "$out" "Security check: no gaps." && ok "security-check: ...and says no gaps" || fail "security-check: no gaps with a note"
green attacks; SEC_IND="not needed" SEC_OWN="$OWN3" SEC_FIND='| 1 | high | Replay accepted | open | SEC-01-003 |' SEC_EXTRA='Risk accepted: #1 high Replay accepted - demo (approved by Sam)' write_sec; printf 'SEC-01-003 fail\n' > "$STUB_RULES"; sc
eq "security-check: an accepted high finding covers it too, exit 0" "$rc" 0
has "$out" "SEC-01-003 fails: finding #1 (accepted)" && ok "security-check: ...noted as accepted" || fail "security-check: accepted note ($out)"
green attacks; SEC_IND="not needed" SEC_OWN="$OWN3" SEC_FIND='' write_sec; printf 'SEC-01-003 fail\n' > "$STUB_RULES"; sc
eq "security-check: the same failure with no finding is a gap, exit 1" "$rc" 1
has "$out" "record a finding in security.md that names SEC-01-003, or fix it" && ok "security-check: ...with the hint" || fail "security-check: hint ($out)"
green attacks; printf 'SEC-01-001 generic\n' > "$STUB_RULES"; sc
eq "security-check: a generic runner passing by exit status exits 0" "$rc" 0
has "$out" "SEC-01-001 [api]: pass (exit status)" && has "$out" "SEC-01-001: generic runner: passed by exit status" && ok "security-check: ...and says how it passed" || fail "security-check: generic note ($out)"
: > "$STUB_RULES"
reset none; sc
eq "security-check: at none, exits 0" "$rc" 0
has "$out" "Recorded level: none" && ok "security-check: at none, says so" || fail "security-check: at none"
has "$out" "Nothing to check at level none." && ok "security-check: ...and that nothing is checked" || fail "security-check: nothing to check"
mv .claude/current-phase "$T/cp"; sc; eq "security-check: no active phase exits 1" "$rc" 1; mv "$T/cp" .claude/current-phase

# signoff-check: the same function, and nothing at none.
reset none; : > "$STUB_CALLS"
out=$(bash "$G/signoff-check.sh"); rc=$?
eq "compat: signoff-check at none, output byte for byte" "$out" "Signoff check: no gaps in $P."
eq "compat: ...exit 0, and no test ran" "$rc/$(calls)" "0/"
out=$(bash "$G/status.sh")
assert "compat: status at none has no security line" test -z "$(grep -i security <<<"$out")"
eq "compat: ...six lines, as before" "$(wc -l <<<"$out" | tr -d ' ')" 6
reset none; add_plan "${GREEN[@]}"; printf 'module=clinic\nnumber=01\nprofile=full\nux=yes\nslug=old\n' > "$P/.plumbline"
out=$(bash "$G/signoff-check.sh"); rc=$?
eq "compat: a plan table and a v0.5 .plumbline with no security key: still no gap" "$out/$rc/$(calls)" "Signoff check: no gaps in $P./0/"
green attacks
out=$(bash "$G/signoff-check.sh"); rc=$?
eq "signoff-check: a green attacks feature has no gaps" "$out/$rc" "Signoff check: no gaps in $P./0"
eq "signoff-check: ...and ran the attack tests" "$(calls)" "api SEC-01-001;web-ui SEC-01-002"
green attacks; plan_level independent; sed -i 's/^Verdict: PASS/Verdict: PENDING/' "$P/qa-report.md"
printf 'SEC-01-002 fail\n' > "$STUB_RULES"
out=$(bash "$G/signoff-check.sh"); rc=$?
so="$out"
eq "signoff-check: gaps exit 1" "$rc" 1
has "$out" "Signoff check: 4 gap(s) in $P:" && ok "signoff-check: v0.4b and security gaps are counted together" || fail "signoff-check: counted ($out)"
has "$out" "- QA verdict is PENDING, not PASS (qa-report.md)" && ok "signoff-check: the v0.4b gap" || fail "signoff-check: v0.4b gap"
has "$out" "- raise not recorded" && ok "signoff-check: an unrecorded raise" || fail "signoff-check: raise"
has "$out" "- attack test did not pass on web-ui: SEC-01-002: fail" && ok "signoff-check: a failing attack test" || fail "signoff-check: attack test"
sc
eq "signoff-check and security-check list the same security gaps" "$(grep "^- " <<<"$so" | grep -v "QA verdict" | sort)" "$(grep "^- " <<<"$out" | sort)"
sed -i 's/^Verdict: PENDING/Verdict: PASS/' "$P/qa-report.md"; : > "$STUB_RULES"

# status: one read-only line.
green attacks; SEC_IND="not needed" SEC_OWN='| SEC-01-003 | api | own | blocked |' SEC_FIND='| 1 | high | Tenant leak | open | x |'$'\n''| 2 | critical | Fixed one | verified | x |'$'\n''| 3 | medium | m | open | x |' write_sec
: > "$STUB_CALLS"; out=$(bash "$G/status.sh")
has "$out" "security: attacks · 2 planned attacks, 1 own · open high 1 · independent pass not needed" && ok "status: the security line" || fail "status: the security line ($(grep security <<<"$out"))"
eq "status: ...runs nothing" "$(calls)" ""
eq "status: ...one line more than at none" "$(wc -l <<<"$out" | tr -d ' ')" 7
green independent; SEC_IND="not started" write_sec; out=$(bash "$G/status.sh")
has "$out" "security: independent · 2 planned attacks, 0 own · open high 0 · independent pass not started" && ok "status: independent, pass not started" || fail "status: independent ($(grep security <<<"$out"))"
rm -f "$SEC"; out=$(bash "$G/status.sh")
has "$out" "security: independent · 2 planned attacks, 0 own · open high 0 · independent pass none" && ok "status: no security.md reads as none" || fail "status: no security.md ($(grep security <<<"$out"))"

# ===== The real node adapter, end to end =====
if command -v node >/dev/null 2>&1; then
  mkdir -p apps/attack
  cat > apps/attack/attack.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
test('AC-01-001 an ordinary acceptance test', () => { assert.strictEqual(1, 2); });
test('SEC-01-001 clinic B cannot read clinic A rooms', () => { assert.strictEqual(1, 1); });
test('SEC-01-002 a forged clinic id is rejected', () => { assert.strictEqual(1, 2); });
EOF
  with_plan '| SEC-01-001 | api-attack | a | b | matches |' '| SEC-01-002 | api-attack | a | b | matches |' '| SEC-01-003 | api-attack | a | b | matches |'
  gp
  assert "node adapter: failing and missing attack tests are gaps (the AC test's failure is not SEC-01-001's)" test -n "$gaps"
  gap "node adapter: the failing run names the attack IDs" "SEC-01-002"
  nogap "node adapter: SEC-01-001 passes; AC-01-001's failure isn't its" "SEC-01-001: fail"
  sed -i 's/assert.strictEqual(1, 2); });$/assert.strictEqual(1, 1); });/' apps/attack/attack.test.js
  printf "test('SEC-01-003 replay is refused', () => {});\n" >> apps/attack/attack.test.js
  gp
  clean "node adapter: every attack test passing is clean"
  rm -rf apps/attack
else
  skip "node adapter end to end (node isn't installed)"
fi

# ===== The ownership guard =====
ENG=aeng-api-e0e49e4975cf862f; SUBAGENT=afd684802d721264c
SECP="$T/repo/$P/security.md"
mk() { # agent id ("" = main session), tool_input JSON, tool name
  jq -nc --arg id "$1" --argjson ti "$2" --arg tool "${3:-Write}" \
    'if $id == "" then {tool_name: $tool, tool_input: $ti} else {tool_name: $tool, agent_id: $id, agent_type: "", tool_input: $ti} end'
}
mkb() { jq -nc --arg id "$1" --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}} + (if $id == "" then {} else {agent_id: $id, agent_type: ""} end)'; }
ti_write() { jq -nc --arg f "$1" --arg c "$2" '{file_path: $f, content: $c}'; }
ti_edit()  { jq -nc --arg f "$1" --arg o "$2" --arg n "$3" '{file_path: $f, old_string: $o, new_string: $n}'; }
check() { # name, expected exit, json
  local got
  echo "$3" | bash "$G/ownership-guard.sh" >/dev/null 2>&1; got=$?
  if [[ $got -eq $2 ]]; then ok "$1"; else fail "$1 (expected $2, got $got)"; fi
}
check_out() { # name, expected exit, json, text the output must contain
  local got out
  out=$(echo "$3" | bash "$G/ownership-guard.sh" 2>&1); got=$?
  if [[ $got -ne $2 ]]; then fail "$1 (expected $2, got $got)"
  elif [[ "$out" != *"$4"* ]]; then fail "$1 (output lacks: $4)"
  else ok "$1"; fi
}
SECMSG="Only the user can waive security work or accept a risk"
RA='Risk accepted: #1 high Tenant leak - demo data (approved by Sam)'
SW='Security waived: attacks - accepted (approved by Sam)'
green attacks; printf 'Notes: x\n' > "$SECP"
check "guard: a subagent's Write of Security waived: to security.md blocked" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" "$SW")")"
check "guard: a teammate's Write of Risk accepted: to security.md blocked" 2 "$(mk "$ENG" "$(ti_write "$SECP" "$RA")")"
check "guard: Edit adding Risk accepted: blocked" 2 "$(mk "$SUBAGENT" "$(ti_edit "$SECP" "Notes: x" "$RA")" Edit)"
check_out "guard: the refusal says only the user can waive or accept" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" "$RA")")" "$SECMSG"
check_out "guard: ...and points at the lead and the build skill" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" "$SW")")" "Tell the lead; the build skill will ask the user."
check "guard: MultiEdit adding the line blocked" 2 "$(mk "$SUBAGENT" "$(jq -nc --arg f "$SECP" --arg c "$RA" '{file_path: $f, edits: [{old_string: "zzz", new_string: "y"}, {old_string: "Notes: x", new_string: $c}]}')" MultiEdit)"
check "guard: a list marker variant blocked" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" "- $RA")")"
check "guard: a bold variant blocked" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" '**Risk accepted:** #1 high Tenant leak - x (approved by Sam)')")"
check "guard: a blockquote variant blocked" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" "> $SW")")"
check "guard: a lowercase variant blocked" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" 'risk accepted: #1 high x - y (approved by Sam)')")"
check "guard: a placeholder-only line blocked" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" 'Security waived: <attacks|independent> - <reason> (approved by <name>)')")"
check "guard: Security waived: pieced together by Edit blocked" 2 "$(mk "$SUBAGENT" "$(ti_edit "$SECP" "Notes: x" "Security waived: attacks - x (approved by Sam)")" Edit)"
check "guard: the main session may write both lines" 0 "$(mk "" "$(ti_write "$SECP" "$SW"$'\n'"$RA")")"
check "guard: the main session may Edit one in" 0 "$(mk "" "$(ti_edit "$SECP" "Notes: x" "$RA")" Edit)"
check "guard: a mention mid-sentence is allowed" 0 "$(mk "$SUBAGENT" "$(ti_write "$SECP" 'Use a Risk accepted: line only when the user says so.')")"
check "guard: a plain write to security.md is allowed" 0 "$(mk "$SUBAGENT" "$(ti_write "$SECP" $'Independent pass: complete (round 1)\n| 1 | high | x | open | y |')")"
printf '# Feature 01 security\n\n%s\n' "$RA" > "$SECP"
check "guard: Edit beside an existing acceptance is allowed" 0 "$(mk "$SUBAGENT" "$(ti_edit "$SECP" "# Feature 01 security" "# Feature 01 security notes")" Edit)"
check "guard: a Write that keeps the existing acceptance and adds a second is blocked" 2 "$(mk "$SUBAGENT" "$(ti_write "$SECP" $'# Feature 01 security\n\n'"$RA"$'\nRisk accepted: #2 high Other - x (approved by Sam)\n')")"
check "guard: changing the existing acceptance is blocked" 2 "$(mk "$SUBAGENT" "$(ti_edit "$SECP" "demo data" "no problem at all")" Edit)"
mkdir -p docs/decisions
check "guard: an ADR with Risk accepted: headings is allowed" 0 "$(mk "$SUBAGENT" "$(ti_write "$T/repo/docs/decisions/0007-risk.md" $'# 0007 Cache\n\n## Risk accepted: stale reads for 5 minutes\nSecurity waived: not applicable here\n')")"
check "guard: SECURITY.md at the repo root is allowed" 0 "$(mk "$SUBAGENT" "$(ti_write "$T/repo/SECURITY.md" $'# Security policy\n\nRisk accepted: none\n')")"
check "guard: a differently named file in the feature folder is allowed" 0 "$(mk "$SUBAGENT" "$(ti_write "$T/repo/$P/threat-model.md" "$RA")")"
check "guard: a SECURITY.MD under docs/product counts as security.md" 2 "$(mk "$SUBAGENT" "$(ti_write "$T/repo/$P/SECURITY.MD" "Risk accepted: #2 high Other - x (approved by Sam)")")"
check "guard: the Evidence waiver lock is as before" 2 "$(mk "$SUBAGENT" "$(ti_write "$T/repo/$P/qa-report.md" 'Evidence waived: transcripts (api) - n/a (approved by Sam)')")"
# Bash: best effort.
SEC_REL="docs/product/clinic/phases/phase-01/security.md"
check_out "guard: Bash echo >> security.md with the phrase blocked, with the security message" 2 "$(mkb "$SUBAGENT" "echo 'Risk accepted: #1 high x - y (approved by Sam)' >> $SEC_REL")" "$SECMSG"
check "guard: Bash heredoc into security.md blocked" 2 "$(mkb "$ENG" $'cat >> '"$SEC_REL"$' <<EOF\nRisk accepted: #1 high x - y (approved by Sam)\nEOF')"
check "guard: Bash tee -a security.md blocked" 2 "$(mkb "$SUBAGENT" "echo 'Security waived: independent - y (approved by Sam)' | tee -a $SEC_REL")"
check "guard: Bash sed -i on security.md with the phrase blocked" 2 "$(mkb "$SUBAGENT" "sed -i 's/^Notes: x/Risk accepted: #1 high x - y (approved by Sam)/' $SEC_REL")"
RAL='Risk accepted: #1 high x - y (approved by Sam)'; SWL='Security waived: attacks - y (approved by Sam)'
check_out "guard: Bash python -c writing the phrase to security.md blocked" 2 "$(mkb "$SUBAGENT" "python -c \"open('$SEC_REL','a').write('$RAL')\"")" "$SECMSG"
check "guard: python3 blocked" 2 "$(mkb "$SUBAGENT" "python3 -c \"open('$SEC_REL','a').write('$RAL')\"")"
check "guard: py -c blocked" 2 "$(mkb "$SUBAGENT" "py -c \"open('$SEC_REL','a').write('$RAL')\"")"
check "guard: node -e blocked" 2 "$(mkb "$ENG" "node -e \"require('fs').appendFileSync('$SEC_REL','$RAL')\"")"
check "guard: ruby blocked" 2 "$(mkb "$SUBAGENT" "ruby -e \"File.write('$SEC_REL', '$RAL')\"")"
check "guard: perl and awk blocked" 2 "$(mkb "$SUBAGENT" "perl -e 'print qq($SWL)' >/dev/null; awk 'BEGIN{print \"$SWL\" > \"$SEC_REL\"}'")"
check "guard: bash -c blocked" 2 "$(mkb "$SUBAGENT" "bash -c \"printf '%s' '$RAL' >> $SEC_REL\"")"
check "guard: pwsh blocked" 2 "$(mkb "$SUBAGENT" "pwsh -Command \"Add-Content $SEC_REL '$RAL'\"")"
check "guard: variable indirection with a redirect blocked" 2 "$(mkb "$SUBAGENT" "f=$SEC_REL; echo '$SWL' >> \$f")"
check "guard: the phrase in any case blocked" 2 "$(mkb "$SUBAGENT" "python -c \"open('$SEC_REL','a').write('RISK ACCEPTED: #1')\"")"
check "guard: cp with the phrase and security.md in the command blocked" 2 "$(mkb "$SUBAGENT" "echo '$RAL' > \$TMPDIR/x && cp \$TMPDIR/x $SEC_REL")"
check "guard: dd blocked" 2 "$(mkb "$SUBAGENT" "printf '%s' '$RAL' | dd of=$SEC_REL")"
check "guard: grep for the phrase in security.md stays allowed" 0 "$(mkb "$SUBAGENT" "grep -n 'Risk accepted:' $SEC_REL")"
check "guard: grep with 2>/dev/null stays allowed" 0 "$(mkb "$SUBAGENT" "grep 'Risk accepted:' $SEC_REL 2>/dev/null")"
check "guard: cat piped to grep stays allowed" 0 "$(mkb "$SUBAGENT" "cat $SEC_REL | grep 'Risk accepted:'")"
check "guard: git log on the phrase stays allowed" 0 "$(mkb "$SUBAGENT" "git log --oneline -S'Risk accepted:' -- $SEC_REL")"
check "guard: git commit -m naming the phrase and security.md stays allowed" 0 "$(mkb "$SUBAGENT" "git commit -m \"docs: risk accepted: stale reads, recorded in security.md\"")"
check "guard: an interpreter that doesn't name security.md is allowed" 0 "$(mkb "$SUBAGENT" "python -c \"print('Risk accepted: x')\"")"
check "guard: an interpreter with security.md but no phrase is allowed" 0 "$(mkb "$SUBAGENT" "python -c \"open('$SEC_REL','a').write('Independent pass: complete (round 1)')\"")"
check "guard: the main session's Bash is allowed" 0 "$(mkb "" "echo 'Risk accepted: #1 high x - y (approved by Sam)' >> $SEC_REL")"
check "guard: grep for the phrase in security.md is allowed" 0 "$(mkb "$SUBAGENT" "grep 'Risk accepted:' $SEC_REL")"
check "guard: git commit -m with the phrase is allowed" 0 "$(mkb "$SUBAGENT" 'git commit -m "risk accepted: stale reads, see the ADR"')"
check "guard: echo of the phrase to another file is allowed" 0 "$(mkb "$SUBAGENT" "echo 'Risk accepted: x' >> docs/decisions/0007-risk.md")"
check "guard: writing security.md without the phrase is allowed" 0 "$(mkb "$SUBAGENT" "echo 'Independent pass: complete (round 1)' >> $SEC_REL")"
check_out "guard: Bash kickoff.sh --set-security blocked, with its own message" 2 "$(mkb "$SUBAGENT" "bash plugins/plumbline/scripts/kickoff.sh --set-security independent")" "kickoff.sh --set-security"
check "guard: Bash kickoff.sh ... --security blocked" 2 "$(mkb "$SUBAGENT" "bash scripts/kickoff.sh orders list --security attacks")"
check "guard: Bash kickoff.sh --security=... blocked" 2 "$(mkb "$ENG" 'bash "$CLAUDE_PLUGIN_ROOT/scripts/kickoff.sh" orders list --security=independent')"
check "guard: kickoff.sh after cd and && blocked" 2 "$(mkb "$SUBAGENT" "cd scripts && bash kickoff.sh --set-security attacks")"
check "guard: the main session may run kickoff.sh --set-security" 0 "$(mkb "" "bash plugins/plumbline/scripts/kickoff.sh --set-security attacks")"
check "guard: kickoff.sh without a security flag is allowed" 0 "$(mkb "$SUBAGENT" "bash plugins/plumbline/scripts/kickoff.sh orders list --profile standard")"
check "guard: git commit -m mentioning the flag is allowed" 0 "$(mkb "$SUBAGENT" 'git commit -m "docs: kickoff.sh --set-security is for the build skill"')"
check "guard: grep for the flag in kickoff.sh is allowed" 0 "$(mkb "$SUBAGENT" "grep -n -e '--set-security' plugins/plumbline/scripts/kickoff.sh")"
# Features at none: the guard doesn't look at levels, so its other behaviour is as before.
reset none
check "guard at none: a subagent's ordinary write is allowed" 0 "$(mk "$SUBAGENT" "$(ti_write "$T/repo/apps/api/x.js" 'x')")"
check "guard at none: a teammate writing outside its globs is still refused" 2 "$(mk "$ENG" "$(ti_write "$T/repo/apps/web/x.js" 'x')")"
check "guard at none: .plumbline is still locked" 2 "$(mk "$SUBAGENT" "$(ti_write "$T/repo/$P/.plumbline" 'security=none')")"

echo
echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
