#!/usr/bin/env bash
# AC test adapter for pytest: runs the tests named after the given AC IDs and
# reports each ID.
#   pytest.sh [--dir <path>] [--surface <s>] "AC-01-001|AC-01-002"
# Runs `python -m pytest -k "ac_01_001 or ac_01_002" -rA -q` in the run folder,
# with the first Python that can import pytest: .venv or venv in the run folder,
# then .venv in the repo root, then python, then python3.
# Prints one line per ID: "AC-01-001: pass (2)", "AC-01-001: fail" or
# "AC-01-001: missing", then the runner's output tail when any ID isn't a pass.
# Exit 0 = every ID has a passing test and none failing; 1 = otherwise, or pytest
# isn't installed; 2 = usage.
#
# Rules: the ID is matched in the whole node ID (file, class, test and
# parameters), as -k matches it. PASSED counts as a pass, FAILED and ERROR as
# fails. SKIPPED, XFAIL and XPASS count as neither, so an ID whose only tests are
# skipped or xfail is "missing". A strict xfail that passes is reported FAILED.
# Subtests (unittest's self.subTest, pytest's subtests fixture): a SUBFAILED line
# is a fail for its test; SUBPASSED, SUBSKIPPED and SUBXFAIL count as neither, as
# the test's own PASSED or FAILED line already counts it.
#
# Verified (Python 3.12.10, pytest 9.0.3, Oct 2026):
# - -k is case-insensitive and matches substrings of names, so "ac_01_001"
#   selects test_AC_01_001_x and TestAC_01_001::test_y. Dashes aren't valid in a
#   -k expression, hence the underscore form; a test with the ID only in a
#   parametrize id written with dashes isn't selected.
# - -rA prints the short summary as "PASSED <nodeid>", "FAILED <nodeid> - msg",
#   "ERROR <nodeid> - msg", "XFAIL <nodeid>", "XPASS <nodeid>" and
#   "SKIPPED [n] <file>:<line>: reason" (no test name, so skips can't be matched).
# - A collection error prints "ERROR <file>" and runs nothing; exit 5 = no tests.
# - Subtests: a failing unittest subTest prints "PASSED <nodeid>" for the test
#   plus "SUBFAILED(i=1) <nodeid> - msg"; a failing subtests-fixture subtest
#   prints "SUBFAILED[msg] (i=1) <nodeid> - msg" and its test turns FAILED. The
#   description is "[msg]", "(k=v, ...)", both, or "(<subtest>)". Passing
#   subtests print nothing in the summary (SUBPASSED only appears in progress
#   lines, at higher verbosity), and a skipped one prints "SUBSKIPPED(...) [n]
#   <file>:<line>: reason". So a unittest test whose subtests are all skipped
#   still reports PASSED and counts as a pass.
# - -p no:cacheprovider keeps .pytest_cache out of the repo.
source "$(dirname "${0//\\//}")/../lib.sh"
NAME=pytest
usage() { echo "usage: $NAME.sh [--dir <path>] [--surface <s>] \"<AC IDs>\"" >&2; exit 2; }

source "$(dirname "${0//\\//}")/common.sh"   # arguments, IDs, run folder, report

# --- Runner ---
py=""
for c in "$run_dir/.venv/bin/python" "$run_dir/.venv/Scripts/python.exe" \
         "$run_dir/venv/bin/python" "$run_dir/venv/Scripts/python.exe" \
         "$PROJECT_DIR/.venv/bin/python" "$PROJECT_DIR/.venv/Scripts/python.exe" \
         python python3; do
  # The Windows Store alias "python3" exists but only prints a hint, so each
  # candidate has to import pytest to be chosen.
  if "$c" -c 'import pytest' >/dev/null 2>&1; then py="$c"; break; fi
done
[[ -n "$py" ]] || { echo "$NAME: not installed"; exit 1; }

kexpr=""
for id in $ids; do
  IFS=- read -r _ a b <<<"$id"
  kexpr="${kexpr:+$kexpr or }ac_${a}_$b"
done

COLUMNS=200 NO_COLOR=1 "$py" -m pytest -k "$kexpr" -rA -q -p no:cacheprovider 2>&1 \
  | tr -d '\r' > "$LOG"
# Summary lines to "status<TAB>node id". A node ID runs to the end of the line, or
# to " - <message>", since parameters may hold spaces. A SUBFAILED line is a fail
# for its test: the known node ID it holds (from that test's PASSED or FAILED
# line), else whatever follows the subtest's "[msg] (params) " description.
awk '
  function id_of(s,   p) { p = index(s, " - "); return p ? substr(s, 1, p - 1) : s }
  /^PASSED /         { s = substr($0, 8); known[s] = 1; print "pass\t" s; next }
  /^(FAILED|ERROR) / { s = id_of(substr($0, index($0, " ") + 1)); known[s] = 1; print "fail\t" s; next }
  /^SUBFAILED/       { sub_[++n] = $0 }
  END {
    for (i = 1; i <= n; i++) {
      line = sub_[i]; best = ""
      for (k in known)
        if (length(k) > length(best) && (index(line, " " k " - ") || substr(line, length(line) - length(k)) == " " k))
          best = k
      if (best == "") {
        s = substr(line, 10)
        if ((p = index(s, ") ")) || (p = index(s, "] "))) s = substr(s, p + 2)
        best = id_of(s)
      }
      print "fail\t" best
    }
  }
' "$LOG" | report
finish $?
