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
T=$(mktemp -d); FXJ="" FXV=""
trap 'rm -rf "$T" ${FXJ:+"$FXJ"} ${FXV:+"$FXV"}' EXIT
mkdir -p "$T/tmp"
export TMPDIR="$T/tmp"
unset CLAUDE_PROJECT_DIR PLUMBLINE_TEST_AC
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
  out=$(grep -E '^AC-[0-9]+-[0-9]+: ' <<<"$all")
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
test('unrelated', () => { assert.fail('not selected'); });
EOF
  common_cases node "$N" node:test "todo"
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
  done
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

@pytest.fixture
def broken(): raise RuntimeError("fixture broke")

def test_ac_01_006_error(broken): pass
def test_unrelated(): assert False
EOF
  common_cases pytest "$P" pytest "xfail/xpass"
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

// A parent here, a leaf with the same name in package b.
func TestAC_01_007(t *testing.T) {
	t.Run("skipped", func(t *testing.T) { t.Skip("later") })
}

// One subtest passes, one is skipped: one pass.
func TestAC_01_008(t *testing.T) {
	t.Run("ok", func(t *testing.T) {})
	t.Run("skipped", func(t *testing.T) { t.Skip("later") })
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
  adapter go "$G" "AC-01-007"; expect "go: same name, parent in one package, leaf in another" 0 "AC-01-007: pass (1)"
  adapter go "$G" "AC-01-008"; expect "go: parent ignored, passing subtest counts" 0 "AC-01-008: pass (1)"
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
gen --surface web-ui "AC-01-001"
if [[ "$rc" == 1 && "$err" == *'no "### web-ui" command block'* ]]; then ok "generic: missing ### surface exits 1, says so"
else fail "generic: missing surface (rc $rc, '$err')"; fi
gen --surface unclosed "AC-01-001"
[[ "$rc" == 1 && "$err" == *"no closing fence"* ]] && ok "generic: unclosed fence exits 1" \
  || fail "generic: unclosed fence (rc $rc, '$err')"
gen "AC-01-001"
[[ "$rc" == 2 ]] && ok "generic: no --surface is a usage error" || fail "generic: no --surface (rc $rc)"
mv "$X/docs/product/project.md" "$X/docs/product/other.md"
gen --surface cli "AC-01-001"
[[ "$rc" == 1 && "$err" == *"project.md not found"* ]] && ok "generic: no project.md exits 1" \
  || fail "generic: no project.md (rc $rc, '$err')"

echo "($((SECONDS - started))s)"
echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
