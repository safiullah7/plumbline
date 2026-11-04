#!/usr/bin/env bash
# Self-test for the AC test adapters (scripts/ac-tests/*.sh), on tiny fixture
# projects run with the real runners: node:test, jest, vitest, pytest and go,
# plus the generic adapter. Run from anywhere:
#   bash tests/adapters-selftest.sh
# A runner that isn't installed is skipped with a note, not failed. jest and
# vitest are installed once into $TMPDIR/plumbline-adapters-npm and reused; with
# no network they are skipped. Works in bash on macOS and Linux, and in Git Bash
# on Windows.
set -u
A="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts/ac-tests"
CACHE="${TMPDIR:-/tmp}/plumbline-adapters-npm"   # before TMPDIR moves below
T=$(mktemp -d); FXJ="" FXV="" FXP="" FXA=""
trap 'rm -rf "$T" ${FXJ:+"$FXJ"} ${FXV:+"$FXV"} ${FXP:+"$FXP"} ${FXA:+"$FXA"}' EXIT
mkdir -p "$T/tmp"
export TMPDIR="$T/tmp"
unset CLAUDE_PROJECT_DIR PLUMBLINE_TEST_AC PLUMBLINE_AC_ALL
# Go's installer adds its folder to PATH only for shells started afterwards.
if ! command -v go >/dev/null 2>&1; then
  for d in "/c/Program Files/Go/bin" /usr/local/go/bin "$HOME/go/bin"; do
    [[ -x "$d/go" || -x "$d/go.exe" ]] && { PATH="$PATH:$d"; break; }
  done
fi
export GOFLAGS=-count=1   # no cached results between runs of this suite
started=$SECONDS

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
skip() { echo "skip  $1"; }
# adapter <name> <project root> [args...]: sets out (the per-ID lines), all
# (stdout and stderr) and rc.
adapter() {
  local name="$1" root="$2"; shift 2
  all=$(CLAUDE_PROJECT_DIR="$root" bash "$A/$name.sh" "$@" 2>&1); rc=$?
  out=$(grep -E '^(AC|SEC)-[0-9]+-[0-9]+: ' <<<"$all")
}
# expect <case> <rc> <per-ID lines, one per argument...>
expect() {
  local name="$1" want_rc="$2" want; shift 2
  want=$(printf '%s\n' "$@")
  if [[ "$rc" == "$want_rc" && "$out" == "$want" ]]; then ok "$name"
  else fail "$name (rc $rc, expected $want_rc)"; printf '%s\n' "$all" | head -n 20 | sed 's/^/      /'
  fi
}
# The same nine cases for every runner, on a fixture with these tests:
#   AC-01-001  two passing tests        AC-01-002  one failing test
#   AC-01-003  skipped only             AC-01-004  todo / xfail / skipped subtests only
#   AC-01-005  lowercase or _ form      AC-261024-01  a Quick ID, passing
#   AC-01-0010 failing (must not count for AC-01-001)
common_cases() { # adapter, fixture root, label
  local a="$1" r="$2" l="$3"
  adapter "$a" "$r" "AC-01-001";   expect "$l: pass, counted" 0 "AC-01-001: pass (2)"
  adapter "$a" "$r" "AC-01-002";   expect "$l: fail" 1 "AC-01-002: fail"
  adapter "$a" "$r" "AC-01-099";   expect "$l: missing" 1 "AC-01-099: missing"
  adapter "$a" "$r" "AC-01-003";   expect "$l: skipped isn't a pass" 1 "AC-01-003: missing"
  adapter "$a" "$r" "AC-01-004";   expect "$l: $4 isn't a pass" 1 "AC-01-004: missing"
  adapter "$a" "$r" "ac_01_005";   expect "$l: underscore/lowercase ID form" 0 "AC-01-005: pass (1)"
  adapter "$a" "$r" "AC-261024-01"; expect "$l: Quick ID" 0 "AC-261024-01: pass (1)"
  adapter "$a" "$r" "AC-01-001|AC-01-099"
  expect "$l: one passes, one missing" 1 "AC-01-001: pass (2)" "AC-01-099: missing"
  adapter "$a" "$r" "AC-01-001, AC-01-002"
  expect "$l: comma list, fail wins" 1 "AC-01-001: pass (2)" "AC-01-002: fail"
}
# The SEC cases for every runner, on a fixture that also has these tests:
#   SEC-01-001 one passing  SEC-01-002 failing  sec_01_003 lowercase, passing
#   SEC-261024-01 passing   AC-07-001 passing (no SEC-07-001 test)
#   SEC-08-001 passing (no AC-08-001 test)
# So a SEC ID selecting an AC test, or the reverse, shows as a wrong line.
sec_cases() { # adapter, fixture root, label
  local a="$1" r="$2" l="$3"
  adapter "$a" "$r" "SEC-01-001";   expect "$l: SEC pass" 0 "SEC-01-001: pass (1)"
  adapter "$a" "$r" "SEC-01-002";   expect "$l: SEC fail" 1 "SEC-01-002: fail"
  adapter "$a" "$r" "SEC-01-099";   expect "$l: SEC missing" 1 "SEC-01-099: missing"
  adapter "$a" "$r" "sec_01_003";   expect "$l: SEC underscore/lowercase form" 0 "SEC-01-003: pass (1)"
  adapter "$a" "$r" "SEC-261024-01"; expect "$l: Quick SEC ID" 0 "SEC-261024-01: pass (1)"
  adapter "$a" "$r" "SEC-07-001";   expect "$l: SEC-07-001 doesn't select AC-07-001's test" 1 "SEC-07-001: missing"
  adapter "$a" "$r" "AC-08-001";    expect "$l: AC-08-001 doesn't select SEC-08-001's test" 1 "AC-08-001: missing"
  adapter "$a" "$r" "AC-07-001|SEC-08-001"
  expect "$l: AC and SEC in one call, both reported" 0 "AC-07-001: pass (1)" "SEC-08-001: pass (1)"
  adapter "$a" "$r" "AC-01-001|SEC-01-002"
  expect "$l: mixed call, SEC fail wins" 1 "AC-01-001: pass (2)" "SEC-01-002: fail"
}
# PATH without the folders holding <tool>, or nothing when one of them also holds
# awk (a shared /usr/bin), since the adapters need it.
path_without() { # tool
  local p="" d IFS=:
  for d in $PATH; do
    if [[ -x "$d/$1" || -x "$d/$1.exe" ]]; then
      [[ -x "$d/awk" || -x "$d/awk.exe" ]] && return 1
      continue
    fi
    p="${p:+$p:}$d"
  done
  printf '%s\n' "$p"
}
not_installed_case() { # adapter, tool, fixture root
  local p
  if p=$(path_without "$2"); then
    all=$(PATH="$p" CLAUDE_PROJECT_DIR="$3" bash "$A/$1.sh" AC-01-001 2>&1); rc=$?
    if [[ "$rc" == 1 && "$all" == "$1: not installed" ]]; then ok "$1: $2 not installed exits 1"
    else fail "$1: $2 not installed (rc $rc, '$all')"; fi
  else
    skip "$1: not-installed case ($2 shares a folder with awk)"
  fi
}

# --- Usage (any adapter; the block is the same in all) ---
mkdir -p "$T/empty"
eq_rc() { [[ "$rc" == "$2" ]] && ok "$1" || fail "$1 (rc $rc)"; }   # case, rc
# The xfail-only trailer: last_is <case> <expected last line>, or "" for no trailer.
last_is() {
  local last; last=$(tail -n 1 <<<"$all")
  if [[ -n "$2" ]]; then [[ "$last" == "$2" ]] && ok "$1" || fail "$1 (last line '$last')"
  else grep -q '^ac-tests: xfail only:' <<<"$all" && fail "$1 (unexpected trailer)" || ok "$1"; fi
}
has_line() { grep -qxF -- "$2" <<<"$all" && ok "$1" || fail "$1 (no line '$2')"; }   # case, line
# The closed-hole hint: hinted <case> <part of the test name>, or "" for no hint at all.
HINT='ac-tests: passed but marked as an expected failure (its hole looks closed: remove the marker and have the finding set to fixed): '
# All-tests mode: an expected failure on a test with no ID is a fail, named on this line.
NOID='ac-tests: an expected failure without a SEC ID is a fail (only an own attack under a deferred or accepted finding may be one): '
hinted() {   # bash matching: grep -iF aborts in some Git Bash locales
  local l found=0
  while IFS= read -r l; do [[ "$l" == "$HINT"*"$2"* ]] && found=1; done <<<"$all"
  if [[ -n "$2" ]]; then (( found )) && ok "$1" || fail "$1 (no hint naming '$2')"
  else (( found )) && fail "$1 (unexpected hint)" || ok "$1"; fi
}
adapter node "$T/empty"; eq_rc "usage: no IDs exits 2" 2
adapter go "$T/empty" "AC-01-001|foo"; eq_rc "usage: a token that isn't an ID exits 2" 2
adapter pytest "$T/empty" --bogus AC-01-001; eq_rc "usage: unknown option exits 2" 2
adapter node "$T/empty" --dir nope AC-01-001; eq_rc "a --dir that doesn't exist exits 1" 1

# --- node:test ---
if command -v node >/dev/null 2>&1; then
  N="$T/node"; mkdir -p "$N/test"
  printf '{ "name": "fx", "private": true }\n' > "$N/package.json"
  cat > "$N/test/ac.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
test('AC-01-001 one', () => {});
test.describe('AC-01-001 suite', () => { test('two', () => {}); });
test('AC-01-002 fails', () => { assert.equal(1, 2); });
test('AC-01-003 skipped', { skip: true }, () => {});
test('AC-01-003 skipped inside', (t) => { t.skip('later'); });
test('AC-01-004 todo', { todo: true }, () => {});
test('AC-01-004 failing todo', { todo: 'later' }, () => { assert.fail('x'); });
test('AC-01-004 parent', async (t) => { await t.test('only a skipped subtest', { skip: true }, () => {}); });
test('ac_01_005 lowercase underscores', () => {});
test('AC-261024-01 quick', () => {});
test('AC-01-0010 other', () => { assert.fail('must not count for AC-01-001'); });
test('SEC-01-001 one', () => {});
test('SEC-01-002 fails', () => { assert.equal(1, 2); });
test('sec_01_003 lowercase underscores', () => {});
test('SEC-261024-01 quick', () => {});
test('AC-07-001 ac only', () => {});
test('SEC-08-001 sec only', () => {});
test('unrelated', () => { assert.fail('not selected'); });
test('AC-10-001 deferred', { todo: 'finding #8 deferred' }, () => { assert.fail('open hole'); });
test('AC-10-002 hole closed', { todo: 'finding #9 deferred' }, () => {});
test('AC-10-003 todo without a finding', { todo: 'later' }, () => { assert.fail('x'); });
test('AC-10-004 titled (Finding #10)', { todo: true }, () => { assert.fail('x'); });
test('AC-10-005 skip naming a finding', { skip: 'finding #11' }, () => {});
EOF
  common_cases node "$N" node:test "todo"
  sec_cases node "$N" node:test
  adapter node "$N" "AC-10-001"
  expect "node:test: a failing todo naming a finding is xfail" 1 "AC-10-001: xfail"
  last_is "node:test: ...with the xfail-only trailer as the last line" "ac-tests: xfail only: AC-10-001"
  adapter node "$N" "AC-10-002"
  expect "node:test: a passing todo naming a finding is a fail (the hole is closed)" 1 "AC-10-002: fail"
  last_is "node:test: ...and no trailer" ""
  hinted "node:test: ...and the closed-hole hint names it" "AC-10-002 hole closed"
  adapter node "$N" "AC-10-003"; expect "node:test: a failing todo without a finding stays missing" 1 "AC-10-003: missing"
  hinted "node:test: no closed-hole hint without a marked test that passed" ""
  last_is "node:test: ...no trailer for missing" ""
  adapter node "$N" "AC-10-004"
  expect "node:test: the title naming a finding is enough (todo: true)" 1 "AC-10-004: xfail"
  adapter node "$N" "AC-10-005"; expect "node:test: a skip naming a finding is still a skip" 1 "AC-10-005: missing"
  adapter node "$N" "AC-10-004|AC-10-001|AC-01-001"
  expect "node:test: xfail next to a pass is still xfail-only" 1 "AC-10-004: xfail" "AC-10-001: xfail" "AC-01-001: pass (2)"
  last_is "node:test: ...trailer sorted, IDs once" "ac-tests: xfail only: AC-10-001 AC-10-004"
  adapter node "$N" "AC-10-001|AC-01-002"
  expect "node:test: a fail beside an xfail: fail, no trailer" 1 "AC-10-001: xfail" "AC-01-002: fail"
  last_is "node:test: ...no trailer when anything failed" ""
  adapter node "$N" "AC-10-001|AC-01-099"
  last_is "node:test: ...nor when an ID is missing" ""
  # All-tests mode: no name filter, IDs optional.
  NA="$T/node-all"; mkdir -p "$NA/test"
  printf '{ "name": "fxa", "private": true }\n' > "$NA/package.json"
  cat > "$NA/test/all.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
test('AC-20-001 ok', () => {});
test('AC-20-002 fails', () => { assert.equal(1, 2); });
test('AC-20-003 deferred', { todo: 'finding #3 deferred' }, () => { assert.fail('open'); });
test('plain ok', () => {});
test('skipped one', { skip: true }, () => {});
test('plain deferred (finding #4)', { todo: true }, () => { assert.fail('open'); });
test('another plain failure', () => { assert.fail('x'); });
EOF
  PLUMBLINE_AC_ALL=1 adapter node "$NA"
  expect "node:test all-tests: no IDs needed, a failing test fails the run" 1
  has_line "node:test all-tests: counts over every test (noid: plain ok, skipped, plain deferred, another; the ID-less xfail is a fail)" "ac-tests: counts 2 1 3 1 4"
  has_line "node:test all-tests: ...the ID-less expected failure is named" "${NOID}plain deferred (finding #4)"
  has_line "node:test all-tests: a failing test is named" "ac-tests: failed: AC-20-002 fails"
  has_line "node:test all-tests: ...every failing test" "ac-tests: failed: another plain failure"
  last_is "node:test all-tests: no trailer when a test failed" ""
  PLUMBLINE_AC_ALL=1 adapter node "$NA" "AC-20-001|AC-20-099|AC-20-003"
  expect "node:test all-tests: given IDs reported pass, missing, xfail" 1 "AC-20-001: pass (1)" "AC-20-099: missing" "AC-20-003: xfail"
  PLUMBLINE_AC_ALL=1 adapter node "$N" "AC-01-002"
  expect "node:test all-tests: the ID's own result, with no filter" 1 "AC-01-002: fail"
  NB="$T/node-allok"; mkdir -p "$NB/test"
  printf '{ "name": "fxb", "private": true }\n' > "$NB/package.json"
  cat > "$NB/test/all.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
test('AC-21-001 ok', () => {});
test('plain ok', () => {});
EOF
  PLUMBLINE_AC_ALL=1 adapter node "$NB"
  expect "node:test all-tests: nothing failed, exit 0" 0
  has_line "node:test all-tests: ...counts" "ac-tests: counts 2 0 0 0 1"
  last_is "node:test all-tests: ...no trailer" ""
  PLUMBLINE_AC_ALL=1 adapter node "$NB" "AC-21-001"
  expect "node:test all-tests: a given passing ID, exit 0" 0 "AC-21-001: pass (1)"
  printf "test('AC-21-002 deferred', { todo: 'finding #5' }, () => { require('node:assert').fail('open'); });\n" >> "$NB/test/all.test.js"
  PLUMBLINE_AC_ALL=1 adapter node "$NB"
  expect "node:test all-tests: an xfail with an ID exits 1 (no per-ID line asked for)" 1
  last_is "node:test all-tests: ...trailer lists every ID'd xfail, requested or not" "ac-tests: xfail only: AC-21-002"
  adapter node "$NB" "AC-21-001"
  expect "node:test: without all-tests mode the filter applies again" 0 "AC-21-001: pass (1)"
  # Monorepo: the root package.json names jest (not installed), the subfolder's
  # doesn't, so a pass proves the run folder's package.json picked node:test.
  M="$T/node-mono"; mkdir -p "$M/apps/web/test"
  printf '{ "name": "root", "private": true, "devDependencies": { "jest": "29.7.0" } }\n' > "$M/package.json"
  printf '{ "name": "web", "private": true }\n' > "$M/apps/web/package.json"
  printf "require('node:test')('AC-02-001 web', () => {});\n" > "$M/apps/web/test/w.test.js"
  adapter node "$M" --dir apps/web "AC-02-001"
  expect "node:test: --dir monorepo subfolder" 0 "AC-02-001: pass (1)"
  adapter node "$M" "AC-02-001" --dir=apps/web
  expect "node:test: --dir=, after the IDs" 0 "AC-02-001: pass (1)"
  adapter node "$M" "AC-02-001"
  if [[ "$rc" == 1 && "$all" == "node: jest: not installed" ]]; then ok "node: root package.json picks jest; not installed exits 1"
  else fail "node: jest not installed (rc $rc, '$all')"; fi
  not_installed_case node node "$N"
else
  skip "node:test (node not installed)"
fi

# --- jest and vitest (npm install once into the cache) ---
have_npm_runners() {
  [[ -x "$CACHE/node_modules/.bin/jest" && -x "$CACHE/node_modules/.bin/vitest" ]] && return 0
  command -v npm >/dev/null 2>&1 || return 1
  mkdir -p "$CACHE" || return 1
  printf '{ "name": "plumbline-adapters-npm", "private": true, "devDependencies": { "jest": "29.7.0", "vitest": "3.2.4" } }\n' \
    > "$CACHE/package.json"
  echo "      (installing jest and vitest into $CACHE, once)"
  (cd "$CACHE" && npm install --no-audit --no-fund --loglevel=error \
     --fetch-retries=1 --fetch-timeout=30000 >/dev/null 2>&1) || return 1
  [[ -x "$CACHE/node_modules/.bin/jest" && -x "$CACHE/node_modules/.bin/vitest" ]]
}
js_tests() { # import line: the same cases as node:test, in jest/vitest syntax
  cat <<EOF
$1
test('AC-01-001 one', () => {});
describe('AC-01-001 suite', () => { test('two', () => {}); });
test('AC-01-002 fails', () => { expect(1).toBe(2); });
test.skip('AC-01-003 skipped', () => {});
test.todo('AC-01-004 todo');
test('ac_01_005 lowercase underscores', () => {});
test('AC-261024-01 quick', () => {});
test('AC-01-0010 other', () => { expect(1).toBe(2); });
test('SEC-01-001 one', () => {});
test('SEC-01-002 fails', () => { expect(1).toBe(2); });
test('sec_01_003 lowercase underscores', () => {});
test('SEC-261024-01 quick', () => {});
test('AC-07-001 ac only', () => {});
test('SEC-08-001 sec only', () => {});
test('unrelated', () => { expect(1).toBe(2); });
EOF
}
if ! command -v node >/dev/null 2>&1; then
  skip "jest/vitest (node not installed)"
elif ! have_npm_runners; then
  skip "jest/vitest (no network)"
else
  # Fixtures live inside the cache so node_modules resolves from the parent, as
  # in a workspace that hoists its runners.
  FXJ=$(mktemp -d "$CACHE/fx-jest.XXXXXX"); FXV=$(mktemp -d "$CACHE/fx-vitest.XXXXXX")
  printf '{ "name": "fxj", "private": true, "devDependencies": { "jest": "29.7.0" } }\n' > "$FXJ/package.json"
  js_tests "" > "$FXJ/ac.test.js"
  printf '{ "name": "fxv", "private": true, "type": "module", "devDependencies": { "vitest": "3.2.4" } }\n' > "$FXV/package.json"
  js_tests "import { test, describe, expect } from 'vitest';" > "$FXV/ac.test.js"
  for r in jest vitest; do
    [[ $r == jest ]] && root="$FXJ" || root="$FXV"
    adapter node "$root" "AC-01-001";    expect "$r: pass, counted (describe name counts)" 0 "AC-01-001: pass (2)"
    adapter node "$root" "AC-01-002";    expect "$r: fail" 1 "AC-01-002: fail"
    adapter node "$root" "AC-01-099";    expect "$r: missing" 1 "AC-01-099: missing"
    adapter node "$root" "AC-01-003";    expect "$r: skipped isn't a pass" 1 "AC-01-003: missing"
    adapter node "$root" "AC-01-004";    expect "$r: todo isn't a pass" 1 "AC-01-004: missing"
    adapter node "$root" "AC_01_005";    expect "$r: underscore ID form" 0 "AC-01-005: pass (1)"
    adapter node "$root" "AC-261024-01|AC-01-099"
    expect "$r: Quick ID passes, other missing" 1 "AC-261024-01: pass (1)" "AC-01-099: missing"
    sec_cases node "$root" "$r"
  done
  # Expected failures: jest test.failing, vitest test.fails (and { fails: true }),
  # read from the source through the test's location. __F__ is the modifier.
  ex_tests() { # import line, modifier
    cat <<EOF
$1
// finding #8 deferred
test.$2('AC-10-001 deferred', () => { expect(1).toBe(2); });
test.$2('AC-10-002 hole closed (finding #9)', () => { expect(1).toBe(1); });
test.$2('AC-10-003 no finding', () => { expect(1).toBe(2); });
test.$2('AC-10-004 titled (finding #10)', () => { expect(1).toBe(2); });
test('AC-10-005 plain test right after one (finding #11)', () => {});
test.$2.each([1, 2])('AC-10-006 each (finding #12) %i', () => { expect(1).toBe(2); });
test.$2(
  'AC-10-007 multi-line call (finding #13)', () => { expect(1).toBe(2); });
describe('AC-10-008 suite (finding #14)', () => { test.$2('inner', () => { expect(1).toBe(2); }); });
test('AC-10-009 plain test mentioning a finding (finding #15)', () => {});
test('AC-10-012 a body holding the flag', () => { expect({ fails: true }).toEqual({ fails: true }); });
EOF
  }
  ex_tests "" failing > "$FXJ/ex.test.js"
  ex_tests "import { test, describe, expect } from 'vitest';" fails > "$FXV/ex.test.js"
  printf "%s\n" "test('AC-10-010 options (finding #16)', { fails: true }, () => { expect(1).toBe(2); });" >> "$FXV/ex.test.js"
  printf "%s\n" "test('AC-10-011 options no finding', { fails: true }, () => { expect(1).toBe(2); });" >> "$FXV/ex.test.js"
  for r in jest vitest; do
    [[ $r == jest ]] && root="$FXJ" || root="$FXV"
    adapter node "$root" "AC-10-001"; expect "$r: a failing-as-expected test with a finding comment is xfail" 1 "AC-10-001: xfail"
    last_is "$r: ...xfail-only trailer is the last line" "ac-tests: xfail only: AC-10-001"
    adapter node "$root" "AC-10-002"
    expect "$r: the marked test passing is a fail (the hole is closed)" 1 "AC-10-002: fail"
    last_is "$r: ...no trailer" ""
    hinted "$r: ...and the closed-hole hint names it" "AC-10-002 hole closed"
    adapter node "$root" "AC-10-003"; expect "$r: the marker without a finding counts as skipped (never a pass), so the ID is missing" 1 "AC-10-003: missing"
    adapter node "$root" "AC-10-012"; expect "$r: { fails: true } inside a one-line body is not the option" 0 "AC-10-012: pass (1)"
    adapter node "$root" "AC-10-004"; expect "$r: the title naming the finding is enough" 1 "AC-10-004: xfail"
    adapter node "$root" "AC-10-005"
    expect "$r: a plain test after a marked one isn't xfail (even naming a finding)" 0 "AC-10-005: pass (1)"
    adapter node "$root" "AC-10-006"; expect "$r: .each on the marker, both cases xfail" 1 "AC-10-006: xfail"
    adapter node "$root" "AC-10-007"; expect "$r: a call spread over lines" 1 "AC-10-007: xfail"
    adapter node "$root" "AC-10-008"; expect "$r: the ID and finding in a describe title" 1 "AC-10-008: xfail"
    adapter node "$root" "AC-10-009"; expect "$r: naming a finding without a marker is a pass" 0 "AC-10-009: pass (1)"
    adapter node "$root" "AC-10-001|AC-10-004|AC-10-005"
    expect "$r: xfail and pass together" 1 "AC-10-001: xfail" "AC-10-004: xfail" "AC-10-005: pass (1)"
    last_is "$r: ...trailer sorted" "ac-tests: xfail only: AC-10-001 AC-10-004"
    adapter node "$root" "AC-10-001|AC-01-002"
    expect "$r: a fail beside an xfail: fail, no trailer" 1 "AC-10-001: xfail" "AC-01-002: fail"
    last_is "$r: ...no trailer" ""
  done
  adapter node "$FXV" "AC-10-010"; expect "vitest: { fails: true } naming a finding is xfail" 1 "AC-10-010: xfail"
  adapter node "$FXV" "AC-10-011"; expect "vitest: { fails: true } without a finding counts as skipped, so the ID is missing" 1 "AC-10-011: missing"
  # All-tests mode, on small projects of their own (a real run of the whole suite).
  FXA=$(mktemp -d "$CACHE/fx-all.XXXXXX"); mkdir -p "$FXA/j" "$FXA/v"
  printf '{ "name": "fxaj", "private": true, "devDependencies": { "jest": "29.7.0" } }\n' > "$FXA/j/package.json"
  printf '{ "name": "fxav", "private": true, "type": "module", "devDependencies": { "vitest": "3.2.4" } }\n' > "$FXA/v/package.json"
  all_tests() { # import line, modifier
    cat <<EOF
$1
test('AC-20-001 ok', () => {});
test('AC-20-002 fails', () => { expect(1).toBe(2); });
// finding #3 deferred
test.$2('AC-20-003 deferred', () => { expect(1).toBe(2); });
test('plain ok', () => {});
test.skip('skipped one', () => {});
test.$2('plain deferred (finding #4)', () => { expect(1).toBe(2); });
test('another plain failure', () => { expect(1).toBe(2); });
EOF
  }
  all_tests "" failing > "$FXA/j/all.test.js"
  all_tests "import { test, expect } from 'vitest';" fails > "$FXA/v/all.test.js"
  for r in jest vitest; do
    [[ $r == jest ]] && root="$FXA/j" || root="$FXA/v"
    PLUMBLINE_AC_ALL=1 adapter node "$root"
    expect "$r all-tests: no IDs needed, failing tests fail the run" 1
    has_line "$r all-tests: counts over every test (xfail counted, noid: plain ok, skipped, plain deferred, another; the ID-less xfail is a fail)" "ac-tests: counts 2 1 3 1 4"
    has_line "$r all-tests: ...the ID-less expected failure is named" "${NOID}plain deferred (finding #4)"
    has_line "$r all-tests: a failing test is named" "ac-tests: failed: AC-20-002 fails"
    has_line "$r all-tests: ...every failing test" "ac-tests: failed: another plain failure"
    last_is "$r all-tests: no trailer when a test failed" ""
    PLUMBLINE_AC_ALL=1 adapter node "$root" "AC-20-001|AC-20-099|AC-20-003"
    expect "$r all-tests: given IDs pass, missing, xfail" 1 "AC-20-001: pass (1)" "AC-20-099: missing" "AC-20-003: xfail"
    # Without the failing tests: xfail only.
    grep -v "fails'\|another plain failure\|plain deferred" "$root/all.test.js" > "$root/ok.test.js"; rm "$root/all.test.js"
    PLUMBLINE_AC_ALL=1 adapter node "$root"
    expect "$r all-tests: an ID'd xfail test exits 1" 1
    has_line "$r all-tests: ...counts" "ac-tests: counts 2 1 0 1 2"
    last_is "$r all-tests: ...trailer lists the unrequested xfail ID" "ac-tests: xfail only: AC-20-003"
  done
fi

# --- playwright: parsing, on recorded JSON (needs only node) ---
# A stand-in `playwright` that writes a recorded report to the file the adapter names
# (or to stdout, as older versions did) and records how it was called.
if command -v node >/dev/null 2>&1; then
  W="$T/pw-fake"; mkdir -p "$W/node_modules/.bin" "$W/apps/web"
  cat > "$W/node_modules/.bin/playwright" <<'EOF'
#!/usr/bin/env bash
echo "$PWD $*" > "$FAKE_ARGS"
if [[ -n "${FAKE_STDOUT:-}" ]]; then cat "$FAKE_JSON"; exit "${FAKE_RC:-1}"; fi
cp "$FAKE_JSON" "$PLAYWRIGHT_JSON_OUTPUT_NAME"
echo "fake playwright output"
exit "${FAKE_RC:-1}"
EOF
  chmod +x "$W/node_modules/.bin/playwright"
  # mkjson <out>: file|path (describes > title)|status|expectedStatus|attempts[|fail annotation],
  # one test per line, to Playwright's JSON shape: suites (files) > suites (describes) >
  # specs > tests > results.
  mkjson() {
    node -e '
      const lines = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean);
      const files = {};
      for (const l of lines) {
        const [file, path, status, expected, attempts, note] = l.split("|");
        const f = files[file] || (files[file] = { title: file, file, specs: [], suites: [] });
        const titles = path.split(" > "), title = titles.pop();
        let s = f;
        for (const t of titles) {
          let c = s.suites.find((x) => x.title === t);
          if (!c) { c = { title: t, file, specs: [], suites: [] }; s.suites.push(c); }
          s = c;
        }
        s.specs.push({ title, ok: status === "expected", file, tests: [{
          projectName: "", expectedStatus: expected, status,
          annotations: note ? [{ type: "fail", description: note }] : [],
          results: attempts.split(",").map((a, i) => ({ status: a, retry: i })) }] });
      }
      const out = { config: {}, suites: Object.values(files), errors: [], stats: {} };
      require("fs").writeFileSync(process.argv[1], JSON.stringify(out));
    ' "$1"
  }
  mkjson "$T/pw.json" <<'EOF'
a.spec.js|AC-01-001 plain|expected|passed|passed
a.spec.js|AC-01-001 other|expected|passed|passed
a.spec.js|AC-01-0010 not the same ID|unexpected|passed|failed
a.spec.js|Checkout > AC-01-002 flaky|flaky|passed|failed,passed
a.spec.js|AC-01-003 interrupted|unexpected|passed|interrupted
a.spec.js|AC-01-004 timed out|unexpected|passed|timedOut
a.spec.js|AC-01-005 marked test.fail|expected|failed|failed
a.spec.js|AC-01-006 skipped|skipped|passed|skipped
a.spec.js|AC-01-007 group > works|expected|passed|passed
a.spec.js|Outer > AC-01-007 inner > works|expected|passed|passed
a.spec.js|AC-01-008 per project|expected|passed|passed
a.spec.js|AC-01-008 per project|unexpected|passed|failed
a.spec.js|AC-01-009 per project|expected|passed|passed
a.spec.js|AC-01-009 per project|expected|passed|passed
AC-01-011.spec.js|works|expected|passed|passed
a.spec.js|   AC-01-012   spaced   |expected|passed|passed
a.spec.js|SEC-01-001 plain|expected|passed|passed
a.spec.js|Attacks > SEC-01-002 bad|unexpected|passed|failed
a.spec.js|AC-07-001 ac only|expected|passed|passed
a.spec.js|SEC-08-001 sec only|expected|passed|passed
a.spec.js|AC-02-001 deferred|expected|failed|failed|finding #8 deferred
a.spec.js|AC-02-002 titled (Finding #9)|expected|failed|failed
a.spec.js|AC-02-003 hole closed|unexpected|failed|passed|finding #8 deferred
a.spec.js|AC-02-004 reason without a finding|expected|failed|failed|just broken
a.spec.js|Deferred > AC-02-005 per project|expected|failed|failed|finding #1
a.spec.js|Deferred > AC-02-005 per project|expected|passed|passed
EOF
  pw_fake() { # root args...: sets out, all and rc, with the recorded report in $T/pw.json
    local root="$1"; shift
    FAKE_JSON="$T/pw.json" FAKE_ARGS="$T/pw.args" adapter playwright "$root" "$@"
  }
  pw_fake "$W" "AC-01-001";   expect "playwright json: pass, counted" 0 "AC-01-001: pass (2)"
  pw_fake "$W" "AC-01-0010";  expect "playwright json: a failure of AC-01-0010 stays with it" 1 "AC-01-0010: fail"
  pw_fake "$W" "AC-01-002";   expect "playwright json: flaky (passed only on a retry) is a fail" 1 "AC-01-002: fail"
  pw_fake "$W" "AC-01-003";   expect "playwright json: interrupted isn't a pass" 1 "AC-01-003: missing"
  pw_fake "$W" "AC-01-004";   expect "playwright json: timedOut is a fail" 1 "AC-01-004: fail"
  pw_fake "$W" "AC-01-005";   expect "playwright json: test.fail (an expected failure) isn't a pass" 1 "AC-01-005: missing"
  pw_fake "$W" "AC-01-006";   expect "playwright json: skipped isn't a pass" 1 "AC-01-006: missing"
  pw_fake "$W" "AC-01-007";   expect "playwright json: the ID in a describe title counts, at any depth" 0 "AC-01-007: pass (2)"
  pw_fake "$W" "AC-01-008";   expect "playwright json: a project's failure fails the ID" 1 "AC-01-008: fail"
  pw_fake "$W" "AC-01-009";   expect "playwright json: every project run is counted" 0 "AC-01-009: pass (2)"
  pw_fake "$W" "AC-01-011";   expect "playwright json: an ID only in the file name isn't a test's" 1 "AC-01-011: missing"
  pw_fake "$W" "AC-01-012";   expect "playwright json: whitespace in a title is collapsed" 0 "AC-01-012: pass (1)"
  pw_fake "$W" "AC-01-001|AC-01-099|AC-01-004"
  expect "playwright json: per-ID lines in the order given" 1 "AC-01-001: pass (2)" "AC-01-099: missing" "AC-01-004: fail"
  pw_fake "$W" "AC-01-001, ac_01_007"
  expect "playwright json: comma list and underscore form" 0 "AC-01-001: pass (2)" "AC-01-007: pass (2)"
  if [[ "$(cat "$T/pw.args")" == */pw-fake" test --grep [Aa][Cc][-_]01[-_]001|[Aa][Cc][-_]01[-_]007 --reporter=json --retries=0" ]]; then
    ok "playwright: the runner is called with --grep <regex>, --reporter=json and --retries=0, in the run folder"
  else fail "playwright: runner arguments ('$(cat "$T/pw.args")')"; fi
  pw_fake "$W" "SEC-01-001";  expect "playwright json: SEC pass" 0 "SEC-01-001: pass (1)"
  pw_fake "$W" "SEC-01-002";  expect "playwright json: SEC fail, ID in a describe title" 1 "SEC-01-002: fail"
  pw_fake "$W" "SEC-01-099";  expect "playwright json: SEC missing" 1 "SEC-01-099: missing"
  pw_fake "$W" "SEC-07-001";  expect "playwright json: SEC-07-001 doesn't select AC-07-001's test" 1 "SEC-07-001: missing"
  pw_fake "$W" "AC-08-001";   expect "playwright json: AC-08-001 doesn't select SEC-08-001's test" 1 "AC-08-001: missing"
  pw_fake "$W" "AC-07-001|SEC-08-001"
  expect "playwright json: AC and SEC in one call" 0 "AC-07-001: pass (1)" "SEC-08-001: pass (1)"
  pw_fake "$W" "AC-01-001, sec_01_001"
  if [[ "$(cat "$T/pw.args")" == */pw-fake" test --grep [Aa][Cc][-_]01[-_]001|[Ss][Ee][Cc][-_]01[-_]001 --reporter=json --retries=0" ]]; then
    ok "playwright: a SEC ID gets its own prefix in the --grep regex"
  else fail "playwright: SEC --grep ('$(cat "$T/pw.args")')"; fi
  pw_fake "$W" --dir apps/web "AC-01-001"
  if [[ "$(cut -d' ' -f1 "$T/pw.args")" == */pw-fake/apps/web && "$out" == "AC-01-001: pass (2)" ]]; then
    ok "playwright: --dir runs it in that folder, finding the bin in a parent's node_modules"
  else fail "playwright: --dir ('$(cat "$T/pw.args")', '$out')"; fi
  FAKE_STDOUT=1 pw_fake "$W" "AC-01-001"; expect "playwright json: older versions' JSON on stdout still reads" 0 "AC-01-001: pass (2)"
  echo 'not json' > "$T/bad.json"
  FAKE_JSON="$T/bad.json" FAKE_ARGS="$T/pw.args" adapter playwright "$W" "AC-01-001"
  if [[ "$rc" == 1 && "$out" == "AC-01-001: missing" && "$all" == *"fake playwright output"* ]]; then
    ok "playwright: unreadable JSON is all missing, exit 1, with the runner's output"
  else fail "playwright: bad JSON (rc $rc, '$all')"; fi
  echo '{"config":{},"suites":[],"errors":[{"message":"boom"}],"stats":{}}' > "$T/empty.json"
  FAKE_JSON="$T/empty.json" FAKE_ARGS="$T/pw.args" adapter playwright "$W" "AC-01-001"
  expect "playwright json: a run with no tests is missing" 1 "AC-01-001: missing"
  # Expected failures: test.fail with a "fail" annotation (the reason) or the title naming a finding.
  pw_fake "$W" "AC-02-001"; expect "playwright json: test.fail whose reason names a finding is xfail" 1 "AC-02-001: xfail"
  last_is "playwright json: ...xfail-only trailer is the last line" "ac-tests: xfail only: AC-02-001"
  pw_fake "$W" "AC-02-002"; expect "playwright json: ...or whose title names it" 1 "AC-02-002: xfail"
  pw_fake "$W" "AC-02-003"; expect "playwright json: the marked test passing (unexpected) is a fail" 1 "AC-02-003: fail"
  last_is "playwright json: ...no trailer" ""
  hinted "playwright json: ...and the closed-hole hint names it" "AC-02-003 hole closed"
  pw_fake "$W" "AC-02-004"; expect "playwright json: a reason without a finding stays missing" 1 "AC-02-004: missing"
  pw_fake "$W" "AC-02-005"; expect "playwright json: per project, xfail and pass is xfail" 1 "AC-02-005: xfail"
  pw_fake "$W" "AC-02-002|AC-02-001|AC-01-001"
  expect "playwright json: xfail beside a pass" 1 "AC-02-002: xfail" "AC-02-001: xfail" "AC-01-001: pass (2)"
  last_is "playwright json: ...trailer sorted" "ac-tests: xfail only: AC-02-001 AC-02-002"
  pw_fake "$W" "AC-02-001|AC-01-004"
  expect "playwright json: a fail beside an xfail: fail, no trailer" 1 "AC-02-001: xfail" "AC-01-004: fail"
  last_is "playwright json: ...no trailer" ""
  # All-tests mode: no --grep, IDs optional, counts over every test.
  mkjson "$T/pw-all.json" <<'EOF'
a.spec.js|AC-30-001 ok|expected|passed|passed
a.spec.js|AC-30-002 bad|unexpected|passed|failed
a.spec.js|AC-30-003 deferred|expected|failed|failed|finding #3 deferred
a.spec.js|plain ok|expected|passed|passed
a.spec.js|skipped one|skipped|passed|skipped
a.spec.js|plain deferred (finding #4)|expected|failed|failed
EOF
  PLUMBLINE_AC_ALL=1 FAKE_JSON="$T/pw-all.json" FAKE_ARGS="$T/pw.args" adapter playwright "$W"
  expect "playwright all-tests: no IDs needed, a failing test fails the run" 1
  has_line "playwright all-tests: counts (noid: plain ok, skipped, plain deferred; the ID-less xfail is a fail)" "ac-tests: counts 2 1 2 1 3"
  has_line "playwright all-tests: ...the ID-less expected failure is named" "${NOID}plain deferred (finding #4)"
  has_line "playwright all-tests: the failing test is named" "ac-tests: failed: AC-30-002 bad"
  if [[ "$(cat "$T/pw.args")" == */pw-fake" test --reporter=json --retries=0" ]]; then
    ok "playwright all-tests: the runner gets no --grep"
  else fail "playwright all-tests: runner arguments ('$(cat "$T/pw.args")')"; fi
  PLUMBLINE_AC_ALL=1 FAKE_JSON="$T/pw-all.json" FAKE_ARGS="$T/pw.args" adapter playwright "$W" "AC-30-001|AC-30-099|AC-30-003"
  expect "playwright all-tests: given IDs pass, missing, xfail" 1 "AC-30-001: pass (1)" "AC-30-099: missing" "AC-30-003: xfail"
  if [[ "$(cat "$T/pw.args")" == */pw-fake" test --reporter=json --retries=0" ]]; then
    ok "playwright all-tests: IDs given, still no --grep"
  else fail "playwright all-tests: runner arguments with IDs ('$(cat "$T/pw.args")')"; fi
  mkjson "$T/pw-allok.json" <<'EOF'
a.spec.js|AC-31-001 ok|expected|passed|passed
a.spec.js|plain deferred (finding #4)|expected|failed|failed
EOF
  PLUMBLINE_AC_ALL=1 FAKE_RC=0 FAKE_JSON="$T/pw-allok.json" FAKE_ARGS="$T/pw.args" adapter playwright "$W"
  expect "playwright all-tests: an ID-less xfail alone fails the run (exit 1)" 1
  has_line "playwright all-tests: ...counts" "ac-tests: counts 1 0 1 0 1"
  last_is "playwright all-tests: ...no trailer" ""
  mkjson "$T/pw-allx.json" <<'EOF'
a.spec.js|AC-31-001 ok|expected|passed|passed
a.spec.js|AC-31-002 deferred|expected|failed|failed|finding #5
EOF
  PLUMBLINE_AC_ALL=1 FAKE_JSON="$T/pw-allx.json" FAKE_ARGS="$T/pw.args" adapter playwright "$W"
  expect "playwright all-tests: an ID'd xfail exits 1" 1
  last_is "playwright all-tests: ...trailer lists it though no ID was asked for" "ac-tests: xfail only: AC-31-002"
  FAKE_JSON="$T/pw-allx.json" FAKE_ARGS="$T/pw.args" adapter playwright "$W"; eq_rc "playwright: no IDs without all-tests mode is a usage error" 2

  # combine.sh on stand-in commands (each ends in a comment, so the appended IDs are ignored)
  comb() { # args...: combine.sh, with CLAUDE_PROJECT_DIR=$W; sets out, all and rc
    adapter combine "$W" "$@"
  }
  comb --cmd "echo 'AC-01-001: pass (2)'; echo 'AC-01-002: pass (1)'; echo 'AC-01-003: missing'; echo 'AC-01-004: fail'; false #" \
       --cmd "echo 'AC-01-001: pass (1)'; echo 'AC-01-002: missing'; echo 'AC-01-003: missing'; echo 'AC-01-004: pass (3)'; false #" \
       "AC-01-001|AC-01-002|AC-01-003|AC-01-004"
  expect "combine: pass sums, one runner is enough, missing in both, fail wins" 1 \
    "AC-01-001: pass (3)" "AC-01-002: pass (1)" "AC-01-003: missing" "AC-01-004: fail"
  comb --cmd "echo 'AC-01-001: pass (2)'; true #" --cmd "echo 'AC-01-001: missing'; false #" "AC-01-001"
  expect "combine: another command's exit 1 for an ID passed elsewhere isn't a failure" 0 "AC-01-001: pass (2)"
  comb --cmd "echo 'AC-01-001: pass (1)'; echo 'AC-01-002: pass (1)' #" "ac_01_002, AC-01-001"
  expect "combine: IDs in the normal form, each once, in the order given" 0 "AC-01-002: pass (1)" "AC-01-001: pass (1)"
  comb --cmd "echo 'AC-01-001: pass (1)' #" --cmd "echo 'playwright: not installed'; false #" "AC-01-001"
  if [[ "$rc" == 1 && "$out" == "AC-01-001: pass (1)" && "$all" == *"playwright: not installed"* ]]; then
    ok "combine: a runner problem (exit 1, no per-ID lines) fails the run and shows its output"
  else fail "combine: runner problem (rc $rc, '$all')"; fi
  comb --cmd "echo hello #" --cmd "echo 'AC-01-001: pass (1)' #" "AC-01-001"
  if [[ "$rc" == 0 && "$out" == "AC-01-001: pass (1)" && "$all" == *"no per-ID lines"* ]]; then
    ok "combine: a command with no lines and exit 0 proves nothing, and says so"
  else fail "combine: no lines (rc $rc, '$all')"; fi
  comb --cmd "echo 'AC-01-001: pass (1)'; printf 'AC-01-002: pass (1)\r\n' #" "AC-01-001|AC-01-002"
  expect "combine: CRLF output is read" 0 "AC-01-001: pass (1)" "AC-01-002: pass (1)"
  comb --cmd "echo 'AC-01-001: fail'; seq 1 60; false #" "AC-01-001"
  if [[ "$rc" == 1 && "$all" == *"(last 40 lines)"* && "$all" == *$'\n60' && "$all" != *$'\n20\n'* ]]; then
    ok "combine: a failing command's output tail is the last 40 lines"
  else fail "combine: tail (rc $rc)"; fi
  comb --cmd "echo 'SEC-01-001: pass (1)'; echo 'SEC-01-002: pass (1)'; echo 'SEC-01-003: missing'; echo 'SEC-01-004: fail'; false #" \
       --cmd "echo 'SEC-01-001: pass (2)'; echo 'SEC-01-002: fail'; echo 'SEC-01-003: missing'; echo 'AC-01-001: pass (1)'; false #" \
       "SEC-01-001|sec_01_002|SEC-01-003|SEC-01-004|AC-01-001"
  expect "combine: SEC lines merge like AC lines, next to an AC line" 1 \
    "SEC-01-001: pass (3)" "SEC-01-002: fail" "SEC-01-003: missing" "SEC-01-004: fail" "AC-01-001: pass (1)"
  comb --cmd "echo 'AC-03-001: pass (1)'; echo 'SEC-03-001: fail' #" --cmd "echo 'SEC-03-001: pass (2)' #" "SEC-03-001|AC-03-001"
  expect "combine: AC-03-001 and SEC-03-001 are separate keys" 1 "SEC-03-001: fail" "AC-03-001: pass (1)"
  comb --cmd "echo 'SEC-01-001: pass (1)' #" "SEC-01-001"
  expect "combine: a SEC-only call" 0 "SEC-01-001: pass (1)"
  comb --cmd "echo 'SEC-01-001: fail'; seq 1 3; false #" "SEC-01-001"
  if [[ "$rc" == 1 && "$all" == *"(last 40 lines)"* && "$all" == *$'\n3' && "$all" != *$'\nSEC-01-001: fail\n1\n'* ]]; then
    ok "combine: a SEC line isn't repeated in the failing command's tail"
  else fail "combine: SEC tail (rc $rc, '$all')"; fi
  comb --cmd "true #" "SEC-01-001|SEX-01-002"; eq_rc "combine: usage: a prefix that isn't AC or SEC exits 2" 2
  comb "AC-01-001"; eq_rc "combine: usage: no --cmd exits 2" 2
  comb --cmd "true #"; eq_rc "combine: usage: no IDs exits 2" 2
  comb --cmd "true #" "AC-01-001|foo"; eq_rc "combine: usage: a token that isn't an ID exits 2" 2
  comb --cmd "  " "AC-01-001"; eq_rc "combine: usage: a blank --cmd exits 2" 2
  comb --bogus --cmd "true #" "AC-01-001"; eq_rc "combine: usage: unknown option exits 2" 2
  comb --cmd "test -d node_modules/.bin && echo 'AC-01-001: pass (1)' #" "AC-01-001"
  expect "combine: commands run in the repo root" 0 "AC-01-001: pass (1)"
  # xfail: any fail -> fail; else any xfail -> xfail; else pass (summed); the trailer last.
  comb --cmd "echo 'AC-01-001: xfail'; echo 'AC-01-002: pass (1)'; echo 'ac-tests: xfail only: AC-01-001'; false #" \
       --cmd "echo 'AC-01-001: pass (2)'; echo 'AC-01-002: pass (2)' #" "AC-01-001|AC-01-002"
  expect "combine: xfail beats pass, passes still sum" 1 "AC-01-001: xfail" "AC-01-002: pass (3)"
  last_is "combine: ...xfail-only trailer is the last line, and nothing else follows" "ac-tests: xfail only: AC-01-001"
  [[ "$all" != *"(last 40 lines)"* ]] && ok "combine: ...no output tail for an xfail-only run" || fail "combine: tail on xfail only"
  comb --cmd "echo 'AC-01-001: xfail'; echo 'ac-tests: xfail only: AC-01-001'; false #" \
       --cmd "echo 'AC-01-001: fail'; false #" "AC-01-001"
  expect "combine: fail beats xfail" 1 "AC-01-001: fail"
  last_is "combine: ...and there is no trailer" ""
  comb --cmd "echo 'AC-01-001: xfail'; echo 'AC-01-002: missing'; false #" "AC-01-001|AC-01-002"
  expect "combine: a missing ID beside an xfail" 1 "AC-01-001: xfail" "AC-01-002: missing"
  last_is "combine: ...no trailer" ""
  comb --cmd "echo 'SEC-01-002: xfail'; echo 'ac-tests: xfail only: SEC-01-002'; false #" \
       --cmd "echo 'AC-01-001: xfail'; echo 'ac-tests: xfail only: AC-01-001'; false #" "SEC-01-002|AC-01-001"
  last_is "combine: both parts' xfail IDs, sorted, once" "ac-tests: xfail only: AC-01-001 SEC-01-002"
  # All-tests mode: counts add up, failed lines and trailers merge, IDs optional.
  PLUMBLINE_AC_ALL=1 comb --cmd "echo 'ac-tests: counts 3 1 0 1 2'; echo 'ac-tests: xfail only: AC-05-002'; false #" \
       --cmd "echo 'ac-tests: counts 4 0 0 0 1'; true #"
  expect "combine all-tests: no IDs, an ID'd xfail exits 1" 1
  has_line "combine all-tests: counts are summed" "ac-tests: counts 7 1 0 1 3"
  last_is "combine all-tests: ...unrequested xfail ID in the trailer" "ac-tests: xfail only: AC-05-002"
  PLUMBLINE_AC_ALL=1 comb --cmd "echo 'ac-tests: counts 3 0 1 0 0'; echo 'ac-tests: failed: AC-05-003 bad'; false #" \
       --cmd "echo 'ac-tests: counts 4 1 0 0 1'; echo 'ac-tests: xfail only: AC-05-002'; false #" "AC-05-001"
  expect "combine all-tests: a failed test fails the run; a given ID nobody reports is missing" 1 "AC-05-001: missing"
  has_line "combine all-tests: ...counts" "ac-tests: counts 7 1 1 0 1"
  has_line "combine all-tests: ...failed lines pass through" "ac-tests: failed: AC-05-003 bad"
  last_is "combine all-tests: ...no trailer when something failed" ""
  PLUMBLINE_AC_ALL=1 comb --cmd "echo 'ac-tests: counts 3 0 0 1 2'; true #" --cmd "echo 'ac-tests: counts 1 0 0 0 0'; true #"
  expect "combine all-tests: everything passed, exit 0" 0
  has_line "combine all-tests: ...summed counts" "ac-tests: counts 4 0 0 1 2"
  PLUMBLINE_AC_ALL=1 comb --cmd "echo 'node: jest: not installed'; false #" --cmd "echo 'ac-tests: counts 1 0 0 0 0'; true #"
  [[ "$rc" == 1 && "$all" == *"node: jest: not installed"* ]] && ok "combine all-tests: a runner problem still fails the run" \
    || fail "combine all-tests: runner problem (rc $rc, '$all')"
  PLUMBLINE_AC_ALL=1 comb --cmd "echo hello #"
  [[ "$rc" == 0 && "$all" != *"no per-ID lines"* ]] && ok "combine all-tests: a raw command judged by exit status, no 'proves nothing' note" \
    || fail "combine all-tests: raw command (rc $rc, '$all')"
  # A raw part gets no IDs in all-tests mode (they would be a filter), with a warning;
  # an adapter part gets them; nobody gets an empty argument.
  # (Each stand-in exits 1 with no per-ID line, so combine shows its output.)
  mkdir -p "$T/cfake/ac-tests"; printf 'echo "nargs=$# first=${1:-}"; exit 1\n' > "$T/cfake/ac-tests/args.sh"
  PLUMBLINE_AC_ALL=1 comb --cmd 'f(){ echo "raw nargs=$#"; return 1; }; f' "AC-05-001"
  [[ "$all" == *"raw nargs=0"* && "$all" == *"ac-check: warning: a raw part runs with no IDs"* ]] && ok "combine all-tests: a raw part runs with no IDs, after a warning" \
    || fail "combine all-tests: raw part arguments ('$all')"
  PLUMBLINE_AC_ALL=1 comb --cmd "bash $T/cfake/ac-tests/args.sh" "AC-05-001"
  [[ "$all" == *"nargs=1 first=AC-05-001"* ]] && ok "combine all-tests: ...an adapter part still gets the IDs" || fail "combine all-tests: adapter part arguments ('$all')"
  PLUMBLINE_AC_ALL=1 comb --cmd "bash $T/cfake/ac-tests/args.sh"
  [[ "$all" == *"nargs=0 first="* ]] && ok "combine all-tests: ...and no empty argument when there are no IDs" || fail "combine all-tests: empty argument ('$all')"
else
  skip "playwright json cases (node not installed)"
fi

# --- playwright: real runs (no browser: the tests don't use one) ---
have_playwright() {
  [[ -x "$CACHE/node_modules/.bin/playwright" ]] && return 0
  command -v npm >/dev/null 2>&1 || return 1
  mkdir -p "$CACHE" || return 1
  echo "      (installing @playwright/test into $CACHE, once)"
  (cd "$CACHE" && { [[ -f package.json ]] || printf '{ "name": "plumbline-adapters-npm", "private": true }\n' > package.json
                    npm install --no-save --no-audit --no-fund --loglevel=error \
                      --fetch-retries=1 --fetch-timeout=30000 @playwright/test@1.64.0 >/dev/null 2>&1; }) || return 1
  [[ -x "$CACHE/node_modules/.bin/playwright" ]]
}
if ! command -v node >/dev/null 2>&1; then
  skip "playwright (node not installed)"
elif ! have_playwright; then
  skip "playwright (no network)"
else
  # Inside the cache, so the bin and @playwright/test resolve from the parent.
  FXP=$(mktemp -d "$CACHE/fx-pw.XXXXXX")
  mkdir -p "$FXP/e2e"
  printf '{ "name": "fxp", "private": true }\n' > "$FXP/package.json"
  # retries: 2 in the config, so the adapter's --retries=0 is what makes AC-01-009 fail.
  printf "module.exports = { testDir: 'e2e', retries: 2, timeout: 1000 };\n" > "$FXP/playwright.config.js"
  cat > "$FXP/e2e/ac.spec.js" <<'EOF'
const { test, expect } = require('@playwright/test');
test('AC-01-001 one', () => { expect(1 + 1).toBe(2); });
test.describe('AC-01-001 suite', () => { test('two', () => { expect(1).toBe(1); }); });
test('AC-01-002 fails', () => { expect(1).toBe(2); });
test.skip('AC-01-003 skipped', () => {});
test('AC-01-003 skipped inside', () => { test.skip(true, 'later'); });
test.fixme('AC-01-004 fixme', () => {});
test('ac_01_005 lowercase underscores', () => {});
test('AC-261024-01 quick', () => {});
test('AC-01-0010 other', () => { expect(1).toBe(2); });
test('SEC-01-001 one', () => {});
test('SEC-01-002 fails', () => { expect(1).toBe(2); });
test('sec_01_003 lowercase underscores', () => {});
test('SEC-261024-01 quick', () => {});
test('AC-07-001 ac only', () => {});
test('SEC-08-001 sec only', () => {});
test('AC-01-006 times out', async () => { await new Promise((r) => setTimeout(r, 3000)); });
test.describe('serial', () => {
  test.describe.configure({ mode: 'serial' });
  test('AC-01-007 first fails', () => { expect(1).toBe(2); });
  test('AC-01-008 not run after it', () => {});
});
test('AC-01-009 flaky: passes only on a retry', ({}, info) => { expect(info.retry).toBeGreaterThan(0); });
test('unrelated', () => { expect(1).toBe(2); });
test('AC-10-001 deferred', () => { test.fail(true, 'finding #8 deferred'); expect(1).toBe(2); });
test('AC-10-002 hole closed', () => { test.fail(true, 'finding #9 deferred'); });
test('AC-10-003 test.fail without a finding', () => { test.fail(); expect(1).toBe(2); });
test('AC-10-004 titled (finding #10)', () => { test.fail(); expect(1).toBe(2); });
test('AC-10-005 reason without a finding', () => { test.fail(true, 'known bug'); expect(1).toBe(2); });
EOF
  common_cases playwright "$FXP" playwright "fixme"
  sec_cases playwright "$FXP" playwright
  adapter playwright "$FXP" "AC-10-001"; expect "playwright: test.fail('finding #8 ...') failing as expected is xfail" 1 "AC-10-001: xfail"
  last_is "playwright: ...xfail-only trailer is the last line" "ac-tests: xfail only: AC-10-001"
  adapter playwright "$FXP" "AC-10-002"; expect "playwright: the marked test passing is a fail" 1 "AC-10-002: fail"
  last_is "playwright: ...no trailer" ""
  hinted "playwright: ...and the closed-hole hint names it" "AC-10-002 hole closed"
  adapter playwright "$FXP" "AC-10-003"; expect "playwright: test.fail without a finding stays missing" 1 "AC-10-003: missing"
  adapter playwright "$FXP" "AC-10-004"; expect "playwright: the title naming a finding is enough" 1 "AC-10-004: xfail"
  adapter playwright "$FXP" "AC-10-005"; expect "playwright: a reason without a finding stays missing" 1 "AC-10-005: missing"
  adapter playwright "$FXP" "AC-01-006";  expect "playwright: a timed-out test is a fail" 1 "AC-01-006: fail"
  adapter playwright "$FXP" "AC-01-007|AC-01-008"
  expect "playwright: a test not run after a serial failure is missing" 1 "AC-01-007: fail" "AC-01-008: missing"
  adapter playwright "$FXP" "AC-01-009"
  expect "playwright: flaky (config retries 2, adapter --retries=0) is a fail" 1 "AC-01-009: fail"
  adapter playwright "$FXP" "AC-01-001" --surface web-ui
  expect "playwright: --surface is accepted and ignored" 0 "AC-01-001: pass (2)"
  adapter playwright "$FXP" "AC-01-002"
  [[ "$all" == *"--- playwright output (last 40 lines) ---"* ]] && ok "playwright: a fail shows the runner's output tail" \
    || fail "playwright: output tail"
  # Monorepo: the bin is hoisted to a parent's node_modules, the config is in the package.
  M="$FXP/mono"; mkdir -p "$M/apps/web/e2e"
  printf '{ "name": "root", "private": true }\n' > "$M/package.json"
  printf '{ "name": "web", "private": true }\n' > "$M/apps/web/package.json"
  printf "module.exports = { testDir: 'e2e' };\n" > "$M/apps/web/playwright.config.js"
  printf "const { test } = require('@playwright/test');\ntest('AC-02-001 web', () => {});\n" > "$M/apps/web/e2e/w.spec.js"
  adapter playwright "$M" --dir apps/web "AC-02-001"
  expect "playwright: --dir monorepo subfolder" 0 "AC-02-001: pass (1)"
  # Not found above the fixture, and npx can't find it either (a global install
  # would): exit 1 with the message.
  mkdir -p "$T/pw-none/e2e" "$T/no-npx"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$T/no-npx/npx"; chmod +x "$T/no-npx/npx"
  all=$(PATH="$T/no-npx:$PATH" CLAUDE_PROJECT_DIR="$T/pw-none" bash "$A/playwright.sh" AC-01-001 2>&1); rc=$?
  if [[ "$rc" == 1 && "$all" == "playwright: not installed" ]]; then ok "playwright: not installed exits 1"
  else fail "playwright: not installed (rc $rc, '$all')"; fi

  # combine.sh over the real runners: node:test and Playwright, one project.
  C="$FXP/combo"; mkdir -p "$C/test" "$C/e2e"
  printf '{ "name": "combo", "private": true }\n' > "$C/package.json"
  printf "module.exports = { testDir: 'e2e' };\n" > "$C/playwright.config.js"
  cat > "$C/test/unit.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
test('AC-05-001 unit only', () => {});
test('AC-05-004 unit passes', () => {});
test('AC-05-005 unit and e2e', () => {});
test('AC-05-006 unit fails', () => { assert.equal(1, 2); });
test('SEC-05-001 unit only', () => {});
test('SEC-05-004 unit passes', () => {});
test('SEC-05-005 unit and e2e', () => {});
EOF
  cat > "$C/e2e/flow.spec.js" <<'EOF'
const { test, expect } = require('@playwright/test');
test('AC-05-002 e2e only', () => {});
test('AC-05-004 e2e fails', () => { expect(1).toBe(2); });
test('AC-05-005 unit and e2e', () => {});
test('AC-05-006 e2e passes', () => {});
test('SEC-05-002 e2e only', () => {});
test('SEC-05-004 e2e fails', () => { expect(1).toBe(2); });
test('SEC-05-005 unit and e2e', () => {});
EOF
  both=(--cmd "bash '$A/node.sh'" --cmd "bash '$A/playwright.sh'")
  adapter combine "$C" "${both[@]}" "AC-05-001|AC-05-002|AC-05-003|AC-05-004|AC-05-005|AC-05-006"
  expect "combine: node + playwright (unit only, e2e only, neither, one fails, both, the other fails)" 1 \
    "AC-05-001: pass (1)" "AC-05-002: pass (1)" "AC-05-003: missing" "AC-05-004: fail" "AC-05-005: pass (2)" "AC-05-006: fail"
  adapter combine "$C" "${both[@]}" "AC-05-001, ac_05_002, AC-05-005"
  expect "combine: ...all passing exits 0" 0 "AC-05-001: pass (1)" "AC-05-002: pass (1)" "AC-05-005: pass (2)"
  adapter combine "$C" "${both[@]}" "SEC-05-001|SEC-05-002|SEC-05-003|SEC-05-004|SEC-05-005|AC-05-005"
  expect "combine: node + playwright with SEC IDs (unit only, e2e only, neither, one fails, both) and an AC ID" 1 \
    "SEC-05-001: pass (1)" "SEC-05-002: pass (1)" "SEC-05-003: missing" "SEC-05-004: fail" "SEC-05-005: pass (2)" "AC-05-005: pass (2)"
  # The same two runners from one --dir each, as a profile cell would write them.
  M2="$FXP/combo2"; mkdir -p "$M2/web/test" "$M2/web/e2e"
  cp "$C/package.json" "$C/playwright.config.js" "$M2/web/"
  cp "$C/test/unit.test.js" "$M2/web/test/"; cp "$C/e2e/flow.spec.js" "$M2/web/e2e/"
  adapter combine "$M2" --cmd "bash '$A/node.sh' --dir web" --cmd "bash '$A/playwright.sh' --dir web" "AC-05-005"
  expect "combine: each command's own --dir" 0 "AC-05-005: pass (2)"
  # A project without Playwright: the runner problem fails the run, node's pass still shows.
  all=$(PATH="$T/no-npx:$PATH" CLAUDE_PROJECT_DIR="$N" bash "$A/combine.sh" "${both[@]}" "AC-01-001" 2>&1); rc=$?
  out=$(grep -E '^(AC|SEC)-[0-9]+-[0-9]+: ' <<<"$all")
  if [[ "$rc" == 1 && "$out" == "AC-01-001: pass (2)" && "$all" == *"playwright: not installed"* ]]; then
    ok "combine: Playwright not installed fails the whole run, saying so"
  else fail "combine: playwright missing (rc $rc, '$all')"; fi
fi

# --- pytest ---
PY=""
for c in python python3; do "$c" -c 'import pytest' >/dev/null 2>&1 && { PY="$c"; break; }; done
if [[ -n "$PY" ]]; then
  P="$T/py"; mkdir -p "$P/tests"
  cat > "$P/tests/test_ac.py" <<'EOF'
import pytest

def test_ac_01_001_one(): pass
def test_AC_01_001_two(): pass
def test_ac_01_002_fails(): assert False

@pytest.mark.skip(reason="later")
def test_ac_01_003_skipped(): pass

@pytest.mark.xfail(reason="known bug")
def test_ac_01_004_xfail(): assert False

@pytest.mark.xfail(reason="non-strict, passes anyway")
def test_ac_01_004_xpass(): pass

class TestAC_01_005:
    def test_inner(self): pass

def test_ac_261024_01_quick(): pass
def test_ac_01_0010_other(): assert False, "must not count for AC-01-001"

def test_sec_01_001_one(): pass
def test_sec_01_002_fails(): assert False
def test_Sec_01_003_lowercase(): pass
def test_sec_261024_01_quick(): pass
def test_ac_07_001_ac_only(): pass
def test_sec_08_001_sec_only(): pass

@pytest.fixture
def broken(): raise RuntimeError("fixture broke")

def test_ac_01_006_error(broken): pass
def test_unrelated(): assert False

@pytest.mark.xfail(strict=True, reason="finding #8 deferred")
def test_ac_10_001_deferred(): assert False

@pytest.mark.xfail(strict=True, reason="finding #9 deferred")
def test_ac_10_002_strict_closed(): pass

@pytest.mark.xfail(reason="finding #10 deferred")
def test_ac_10_003_nonstrict_closed(): pass

@pytest.mark.xfail(strict=True, reason="known bug")
def test_ac_10_004_no_finding(): assert False

@pytest.mark.xfail(reason="known bug")
def test_ac_10_005_nonstrict_pass(): pass

@pytest.mark.parametrize("x", ["(finding #11)"])
@pytest.mark.xfail
def test_ac_10_006_title(x): assert False

@pytest.mark.skip(reason="finding #12 deferred")
def test_ac_10_007_skip(): pass
EOF
  common_cases pytest "$P" pytest "xfail/xpass"
  sec_cases pytest "$P" pytest
  adapter pytest "$P" "AC-10-001"; expect "pytest: strict xfail naming a finding is xfail" 1 "AC-10-001: xfail"
  last_is "pytest: ...xfail-only trailer is the last line" "ac-tests: xfail only: AC-10-001"
  adapter pytest "$P" "AC-10-002"; expect "pytest: ...strict, it passing is a fail" 1 "AC-10-002: fail"
  last_is "pytest: ...no trailer" ""
  hinted "pytest: ...and the closed-hole hint names it" "test_ac_10_002_strict_closed"
  adapter pytest "$P" "AC-10-003"; expect "pytest: non-strict XPASS naming a finding is a fail" 1 "AC-10-003: fail"
  hinted "pytest: ...with the closed-hole hint" "test_ac_10_003_nonstrict_closed"
  adapter pytest "$P" "AC-10-004"; expect "pytest: xfail without a finding stays missing" 1 "AC-10-004: missing"
  adapter pytest "$P" "AC-10-005"; expect "pytest: non-strict XPASS without a finding stays missing" 1 "AC-10-005: missing"
  adapter pytest "$P" "AC-10-006"; expect "pytest: the parameter id naming a finding is enough" 1 "AC-10-006: xfail"
  adapter pytest "$P" "AC-10-007"; expect "pytest: a skip naming a finding is still a skip" 1 "AC-10-007: missing"
  adapter pytest "$P" "AC-10-006|AC-10-001|AC-01-001"
  expect "pytest: xfail beside a pass" 1 "AC-10-006: xfail" "AC-10-001: xfail" "AC-01-001: pass (2)"
  last_is "pytest: ...trailer sorted" "ac-tests: xfail only: AC-10-001 AC-10-006"
  adapter pytest "$P" "AC-10-001|AC-01-002"
  expect "pytest: a fail beside an xfail: fail, no trailer" 1 "AC-10-001: xfail" "AC-01-002: fail"
  last_is "pytest: ...no trailer" ""
  # All-tests mode: no -k, IDs optional.
  PA="$T/py-all"; mkdir -p "$PA/tests"
  cat > "$PA/tests/test_all.py" <<'EOF'
import pytest

def test_ac_20_001_ok(): pass
def test_ac_20_002_fails(): assert False

@pytest.mark.xfail(strict=True, reason="finding #3 deferred")
def test_ac_20_003_deferred(): assert False

def test_plain_ok(): pass

@pytest.mark.skip(reason="later")
def test_skipped_one(): pass

@pytest.mark.xfail(strict=True, reason="finding #4 deferred")
def test_plain_deferred(): assert False

def test_another_plain_failure(): assert False
EOF
  PLUMBLINE_AC_ALL=1 adapter pytest "$PA"
  expect "pytest all-tests: no IDs needed, failing tests fail the run" 1
  has_line "pytest all-tests: counts (noid: plain ok, skipped, plain deferred, another; the ID-less xfail is a fail)" "ac-tests: counts 2 1 3 1 4"
  has_line "pytest all-tests: ...the ID-less expected failure is named" "${NOID}tests/test_all.py::test_plain_deferred"
  has_line "pytest all-tests: a failing test is named" "ac-tests: failed: tests/test_all.py::test_ac_20_002_fails"
  last_is "pytest all-tests: no trailer when a test failed" ""
  PLUMBLINE_AC_ALL=1 adapter pytest "$PA" "AC-20-001|AC-20-099|AC-20-003"
  expect "pytest all-tests: given IDs pass, missing, xfail" 1 "AC-20-001: pass (1)" "AC-20-099: missing" "AC-20-003: xfail"
  PB="$T/py-allok"; mkdir -p "$PB/tests"
  printf 'import pytest\n\ndef test_ac_21_001_ok(): pass\n\n@pytest.mark.xfail(strict=True, reason="finding #4 deferred")\ndef test_plain_deferred(): assert False\n' > "$PB/tests/test_ok.py"
  PLUMBLINE_AC_ALL=1 adapter pytest "$PB"
  expect "pytest all-tests: an ID-less xfail alone fails the run (exit 1)" 1
  has_line "pytest all-tests: ...counts" "ac-tests: counts 1 0 1 0 1"
  printf 'import pytest\n\ndef test_ac_21_001_ok(): pass\n\n@pytest.mark.xfail(strict=True, reason="finding #5 deferred")\ndef test_ac_21_002_deferred(): assert False\n' > "$PB/tests/test_ok.py"
  PLUMBLINE_AC_ALL=1 adapter pytest "$PB"
  expect "pytest all-tests: an ID'd xfail exits 1" 1
  last_is "pytest all-tests: ...trailer lists the unrequested xfail ID" "ac-tests: xfail only: AC-21-002"
  adapter pytest "$P" "AC-01-006"; expect "pytest: ERROR counts as fail" 1 "AC-01-006: fail"
  # Subtests (pytest 9): a failing unittest subTest leaves its test PASSED plus a
  # SUBFAILED line; parameters and subtest messages may hold spaces.
  SB="$T/py-sub"; mkdir -p "$SB/tests"
  cat > "$SB/tests/test_sub.py" <<'EOF'
import unittest
import pytest

class TestAC_03_001(unittest.TestCase):
    def test_loop(self):
        for i in range(3):
            with self.subTest(i=i, label="a b) c"):
                self.assertNotEqual(i, 1)

class TestAC_03_002(unittest.TestCase):
    def test_loop(self):
        for i in range(2):
            with self.subTest(i=i):
                pass

class TestAC_03_003(unittest.TestCase):
    def test_plain(self):
        with self.subTest():
            self.fail("no description")

def test_ac_03_004_fixture(subtests):
    for i in range(2):
        with subtests.test(msg="has ] and ) in it", i=i):
            assert i == 0

def test_ac_03_005_fixture_ok(subtests):
    with subtests.test(msg="fine"):
        pass

@pytest.mark.parametrize("x", ["a b", "c - d"])
def test_ac_03_006_param(x): pass

@pytest.mark.parametrize("x", ["a b", "c - d"])
def test_ac_03_007_param(x): assert x == "a b"
EOF
  if "$PY" -c 'import sys, pytest; sys.exit(int(pytest.__version__.split(".")[0]) < 9)' 2>/dev/null; then
    adapter pytest "$SB" "AC-03-001"; expect "pytest: a failing unittest subTest is a fail" 1 "AC-03-001: fail"
    adapter pytest "$SB" "AC-03-002"; expect "pytest: passing subTests are one pass" 0 "AC-03-002: pass (1)"
    adapter pytest "$SB" "AC-03-003"; expect "pytest: a failing subTest without a description" 1 "AC-03-003: fail"
    adapter pytest "$SB" "AC-03-004"; expect "pytest: a failing subtests-fixture subtest" 1 "AC-03-004: fail"
    adapter pytest "$SB" "AC-03-005"; expect "pytest: a passing subtests-fixture subtest" 0 "AC-03-005: pass (1)"
    adapter pytest "$SB" "AC-03-006"; expect "pytest: parameters with spaces and ' - '" 0 "AC-03-006: pass (2)"
    adapter pytest "$SB" "AC-03-007"; expect "pytest: ...one of them failing" 1 "AC-03-007: fail"
    adapter pytest "$SB" "AC-03-002|AC-03-001"
    expect "pytest: a subtest fail stays with its own ID" 1 "AC-03-002: pass (1)" "AC-03-001: fail"
  else
    skip "pytest: subtest cases (pytest older than 9)"
  fi
  M="$T/py-mono"; mkdir -p "$M/services/data/tests"
  printf 'def test_ac_02_001_data(): pass\n' > "$M/services/data/tests/test_data.py"
  adapter pytest "$M" --dir services/data "AC-02-001"
  expect "pytest: --dir monorepo subfolder" 0 "AC-02-001: pass (1)"
  not_installed_case pytest python "$P"
else
  skip "pytest (no python with pytest)"
fi

# --- go ---
if command -v go >/dev/null 2>&1; then
  G="$T/go"; mkdir -p "$G/pkg/a" "$G/pkg/b"
  printf 'module example.com/fx\n\ngo 1.21\n' > "$G/go.mod"
  cat > "$G/pkg/a/a_test.go" <<'EOF'
package a

import "testing"

func TestAC_01_001(t *testing.T)     {}
func TestAC_01_002Fail(t *testing.T) { t.Fatal("bad") }
func TestAC_01_003Skip(t *testing.T) { t.Skip("later") }

// A parent whose only subtest is skipped passes in Go; it mustn't count here.
func TestAC_01_004Parent(t *testing.T) {
	t.Run("skipped", func(t *testing.T) { t.Skip("later") })
}

func TestAc_01_005(t *testing.T)        {}
func TestAC_261024_01Quick(t *testing.T) {}
func TestAC_01_0010(t *testing.T)       { t.Fatal("must not count for AC-01-001") }

func TestSEC_01_001(t *testing.T)         {}
func TestSEC_01_002Fail(t *testing.T)     { t.Fatal("bad") }
func TestSec_01_003(t *testing.T)         {}
func TestSEC_261024_01Quick(t *testing.T) {}
func TestAC_07_001(t *testing.T)          {}
func TestSEC_08_001(t *testing.T)         {}

// A parent here, a leaf with the same name in package b.
func TestAC_01_007(t *testing.T) {
	t.Run("skipped", func(t *testing.T) { t.Skip("later") })
}

// One subtest passes, one is skipped: one pass.
func TestAC_01_008(t *testing.T) {
	t.Run("ok", func(t *testing.T) {})
	t.Run("skipped", func(t *testing.T) { t.Skip("later") })
}

// Expected failures: a skip whose message says "xfail: finding #n".
func TestAC_10_001(t *testing.T) { t.Skip("xfail: finding #8 deferred") }
func TestAC_10_002(t *testing.T) { t.Skip("xfail: later") }
func TestAC_10_003(t *testing.T) { t.Skip("finding #9 deferred") }
func TestAC_10_004(t *testing.T) {
	t.Run("sub", func(t *testing.T) { t.Skip("xfail: finding #10 deferred") })
}
EOF
  cat > "$G/pkg/b/b_test.go" <<'EOF'
package b

import "testing"

func TestAC_01_001InB(t *testing.T) {}
func TestAC_01_007(t *testing.T)    {}
EOF
  # AC-01-001 has TestAC_01_001 and TestAC_01_001InB: the "two passing tests".
  common_cases go "$G" go "skipped-subtests parent"
  sec_cases go "$G" go
  adapter go "$G" "AC-01-007"; expect "go: same name, parent in one package, leaf in another" 0 "AC-01-007: pass (1)"
  adapter go "$G" "AC-01-008"; expect "go: parent ignored, passing subtest counts" 0 "AC-01-008: pass (1)"
  adapter go "$G" "AC-10-001"; expect "go: a skip saying 'xfail: finding #n' is xfail" 1 "AC-10-001: xfail"
  last_is "go: ...xfail-only trailer is the last line" "ac-tests: xfail only: AC-10-001"
  adapter go "$G" "AC-10-002"; expect "go: 'xfail:' without a finding stays a skip (missing)" 1 "AC-10-002: missing"
  adapter go "$G" "AC-10-003"; expect "go: a finding without 'xfail:' stays a skip (missing)" 1 "AC-10-003: missing"
  adapter go "$G" "AC-10-004"; expect "go: a parent with an xfail subtest reports the subtest" 1 "AC-10-004: xfail"
  adapter go "$G" "AC-10-001|AC-01-001"
  expect "go: xfail beside a pass" 1 "AC-10-001: xfail" "AC-01-001: pass (2)"
  last_is "go: ...trailer" "ac-tests: xfail only: AC-10-001"
  adapter go "$G" "AC-10-001|AC-01-002"
  expect "go: a fail beside an xfail: fail, no trailer" 1 "AC-10-001: xfail" "AC-01-002: fail"
  last_is "go: ...no trailer" ""
  [[ "$all" == *"--- go output (last 40 lines) ---"* && "$all" == *"bad"* ]] && ok "go: the output tail is readable text (not JSON events)" \
    || fail "go: output tail ('$all')"
  # All-tests mode: no -run, IDs optional.
  GA="$T/go-all"; mkdir -p "$GA/ok" "$GA/broken"
  printf 'module example.com/fxa\n\ngo 1.21\n' > "$GA/go.mod"
  cat > "$GA/ok/ok_test.go" <<'EOF'
package ok

import "testing"

func TestAC_20_001(t *testing.T)     {}
func TestAC_20_002Fail(t *testing.T) { t.Fatal("bad") }
func TestAC_20_003(t *testing.T)     { t.Skip("xfail: finding #3 deferred") }
func TestPlainOk(t *testing.T)       {}
func TestSkippedOne(t *testing.T)    { t.Skip("later") }
func TestPlainDeferred(t *testing.T) { t.Skip("xfail: finding #4 deferred") }
func TestAnotherFailure(t *testing.T) { t.Fatal("bad") }
EOF
  printf 'package broken\n\nimport "testing"\n\nfunc TestBroken(t *testing.T) { this does not compile }\n' > "$GA/broken/b_test.go"
  PLUMBLINE_AC_ALL=1 adapter go "$GA"
  expect "go all-tests: no IDs needed, failing tests fail the run" 1
  has_line "go all-tests: counts (a package that doesn't build is one failed test; the ID-less xfail is a fail)" "ac-tests: counts 2 1 4 1 5"
  has_line "go all-tests: ...the ID-less expected failure is named" "${NOID}TestPlainDeferred"
  has_line "go all-tests: a failing test is named" "ac-tests: failed: TestAC_20_002Fail"
  has_line "go all-tests: ...the package that failed to build" "ac-tests: failed: example.com/fxa/broken (package failed)"
  PLUMBLINE_AC_ALL=1 adapter go "$GA" "AC-20-001|AC-20-099|AC-20-003"
  expect "go all-tests: given IDs pass, missing, xfail" 1 "AC-20-001: pass (1)" "AC-20-099: missing" "AC-20-003: xfail"
  rm -rf "$GA/broken"
  sed -i '/TestAC_20_002Fail\|TestAnotherFailure\|TestPlainDeferred/d' "$GA/ok/ok_test.go"
  PLUMBLINE_AC_ALL=1 adapter go "$GA"
  expect "go all-tests: an ID'd xfail test exits 1" 1
  has_line "go all-tests: ...counts" "ac-tests: counts 2 1 0 1 2"
  last_is "go all-tests: ...trailer lists the unrequested xfail ID" "ac-tests: xfail only: AC-20-003"
  M="$T/go-mono"; mkdir -p "$M/services/api"
  printf 'module example.com/api\n\ngo 1.21\n' > "$M/services/api/go.mod"
  printf 'package api\n\nimport "testing"\n\nfunc TestAC_02_001(t *testing.T) {}\n' > "$M/services/api/api_test.go"
  adapter go "$M" --dir services/api "AC-02-001"
  expect "go: --dir monorepo subfolder" 0 "AC-02-001: pass (1)"
  adapter go "$M" "AC-02-001"
  expect "go: without --dir the root has no module" 1 "AC-02-001: missing"
  not_installed_case go go "$G"
else
  skip "go (not installed)"
fi

# --- generic ---
X="$T/gen"; mkdir -p "$X/docs/product" "$X/sub"
: > "$X/root-marker"
# CRLF on purpose: Windows editors save project.md that way.
awk '{ printf "%s\r\n", $0 }' > "$X/docs/product/project.md" <<'EOF'
# Project

## Surfaces
| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |
| --- | --- | --- | --- | --- | --- | --- |
| cli | Rust | ** | cargo run | cargo check | cargo clippy | generic |

## Generic commands

### cli
Runs in the repo root.
```bash
test -f root-marker || { echo "not in the repo root"; exit 9; }
echo "regex={ids_regex}"
echo "under={ids_underscored}"
```

### failing
```
echo "running {ids_underscored}"; exit 3
```

### unclosed
~~~
echo never

## Other notes

### api
```
echo "from the wrong section"
```
EOF
gen() { # args...: sets out (stdout), err, rc
  out=$(CLAUDE_PROJECT_DIR="$X" bash "$A/generic.sh" "$@" 2>"$T/err"); rc=$?
  err=$(tr -d '\r' < "$T/err")
}
warning="generic: per-ID presence isn't proven; the command's exit code is the result."
gen --surface cli "AC-01-001|ac_01_002"
if [[ "$rc" == 0 && "$out" == $'regex=AC[-_]01[-_]001|AC[-_]01[-_]002\nunder=AC_01_001 AC_01_002' ]]; then
  ok "generic: placeholders substituted, run in the repo root, CRLF file"
else fail "generic: placeholders (rc $rc, '$out', '$err')"; fi
[[ "$err" == "$warning" ]] && ok "generic: the warning goes to stderr" || fail "generic: warning ('$err')"
gen "AC-261024-01" --surface failing
[[ "$rc" == 3 && "$out" == "running AC_261024_01" ]] && ok "generic: exit code passes through (3)" \
  || fail "generic: exit code (rc $rc, '$out')"
grep -qxF "$warning" <<<"$err" && ok "generic: warning on a failing command too" || fail "generic: warning on failure"
gen --surface api "AC-01-001"
if [[ "$rc" == 1 && "$err" == *'no "### api" command block under "## Generic commands"'* ]]; then
  ok "generic: a ### under another section isn't used"
else fail "generic: wrong section (rc $rc, '$out', '$err')"; fi
gen --surface cli "SEC-03-001|sec_03_002, AC-03-001"
if [[ "$rc" == 0 && "$out" == $'regex=SEC[-_]03[-_]001|SEC[-_]03[-_]002|AC[-_]03[-_]001\nunder=SEC_03_001 SEC_03_002 AC_03_001' ]]; then
  ok "generic: SEC IDs keep their prefix in both placeholders, AC IDs stay as they were"
else fail "generic: SEC placeholders (rc $rc, '$out', '$err')"; fi
gen --surface cli "SEC-261024-01"
[[ "$rc" == 0 && "$out" == $'regex=SEC[-_]261024[-_]01\nunder=SEC_261024_01' ]] && ok "generic: Quick SEC ID" \
  || fail "generic: Quick SEC ID (rc $rc, '$out')"
# The regex must not select the other prefix's names (as go test -run or grep would).
names=$'TestAC_03_001\nTestSEC_03_001\nac-03-001 works\nSEC-03-001 works'
gen --surface cli "SEC-03-001"
re=$(sed -n 's/^regex=//p' <<<"$out")
[[ "$(grep -E "$re" <<<"$names" | paste -sd, -)" == "TestSEC_03_001,SEC-03-001 works" ]] \
  && ok "generic: SEC-03-001's regex never selects AC-03-001's test" || fail "generic: SEC regex ('$re')"
gen --surface cli "AC-03-001"
re=$(sed -n 's/^regex=//p' <<<"$out")
[[ "$(grep -E "$re" <<<"$names" | paste -sd, -)" == "TestAC_03_001" ]] \
  && ok "generic: AC-03-001's regex never selects SEC-03-001's test" || fail "generic: AC regex ('$re')"
gen --surface cli "SEC-01-001|SEX-01-002"
[[ "$rc" == 2 ]] && ok "generic: a prefix that isn't AC or SEC is a usage error" || fail "generic: bad prefix (rc $rc)"
gen --surface web-ui "AC-01-001"
if [[ "$rc" == 1 && "$err" == *'no "### web-ui" command block'* ]]; then ok "generic: missing ### surface exits 1, says so"
else fail "generic: missing surface (rc $rc, '$err')"; fi
gen --surface unclosed "AC-01-001"
[[ "$rc" == 1 && "$err" == *"no closing fence"* ]] && ok "generic: unclosed fence exits 1" \
  || fail "generic: unclosed fence (rc $rc, '$err')"
gen "AC-01-001"
[[ "$rc" == 2 ]] && ok "generic: no --surface is a usage error" || fail "generic: no --surface (rc $rc)"
gen --surface cli; [[ "$rc" == 2 ]] && ok "generic: no IDs is a usage error outside all-tests mode" || fail "generic: no IDs (rc $rc)"
PLUMBLINE_AC_ALL=1 gen --surface cli
if [[ "$rc" == 0 && "$out" == $'regex=.\nunder=' && "$err" == "$warning" ]]; then
  ok "generic all-tests: no IDs, {ids_regex} is '.', {ids_underscored} empty, the warning stays, no counts line"
else fail "generic all-tests: (rc $rc, '$out', '$err')"; fi
PLUMBLINE_AC_ALL=1 gen --surface cli "AC-01-001"
[[ "$rc" == 0 && "$out" == $'regex=.\nunder=' ]] && ok "generic all-tests: given IDs are not substituted" \
  || fail "generic all-tests with IDs (rc $rc, '$out')"
PLUMBLINE_AC_ALL=1 gen --surface failing
[[ "$rc" == 3 ]] && ok "generic all-tests: judged by the command's exit status" || fail "generic all-tests: exit (rc $rc)"
mv "$X/docs/product/project.md" "$X/docs/product/other.md"
gen --surface cli "AC-01-001"
[[ "$rc" == 1 && "$err" == *"project.md not found"* ]] && ok "generic: no project.md exits 1" \
  || fail "generic: no project.md (rc $rc, '$err')"

echo "($((SECONDS - started))s)"
echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
