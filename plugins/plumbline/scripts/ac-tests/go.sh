#!/usr/bin/env bash
# AC test adapter for Go: runs the tests named after the given AC IDs and reports
# each ID.
#   go.sh [--dir <path>] [--surface <s>] "AC-01-001|AC-01-002"
# Runs `go test ./... -run '[Aa][Cc][-_]01[-_]001|...' -v` in the run folder.
# Prints one line per ID: "AC-01-001: pass (2)", "AC-01-001: fail" or
# "AC-01-001: missing", then the runner's output tail when any ID isn't a pass.
# Exit 0 = every ID has a passing test and none failing; 1 = otherwise, or go
# isn't installed; 2 = usage.
#
# Rules: the ID goes in the top-level test name (TestAC_01_001, TestAc_01_001_Login);
# subtests inherit it through their "Parent/sub" names. Only leaf tests count: a
# test with subtests adds nothing when it passes, so a parent whose subtests are
# all skipped is "missing", not a pass. A failing parent still counts as a fail.
# SKIP lines count as neither pass nor fail.
#
# Verified (go1.27.0 windows/amd64, `go help testflag`, Oct 2026):
# - -run is a regex split on unbracketed "/" into one regex per subtest level;
#   only the top level is given here, so an ID that appears only in a subtest
#   name isn't selected. Matching is case-sensitive, hence [Aa][Cc].
# - -v prints "--- PASS: Name (0.00s)", "--- FAIL: ...", "--- SKIP: ...", with
#   subtests as "Parent/sub" indented 4 spaces per level after the parent's line,
#   then "ok  <pkg>" or "FAIL <pkg>" per package. A package that doesn't build
#   prints "FAIL <pkg> [build failed]" and no test lines. Cached results replay
#   the same lines.
source "$(dirname "${0//\\//}")/../lib.sh"
NAME=go
usage() { echo "usage: $NAME.sh [--dir <path>] [--surface <s>] \"<AC IDs>\"" >&2; exit 2; }

source "$(dirname "${0//\\//}")/common.sh"   # arguments, IDs, run folder, report

# --- Runner ---
command -v go >/dev/null 2>&1 || { echo "$NAME: not installed"; exit 1; }

go test ./... -run "$re" -v 2>&1 | tr -d '\r' > "$LOG"
# Result lines to "status<TAB>test name", one package at a time (two packages may
# use the same test name): a name with a "name/..." result in the same package is
# a parent, and only reports its fails.
awk '
  function flush(   i, j, parent) {
    for (i = 1; i <= n; i++) {
      parent = 0
      for (j = 1; j <= n; j++)
        if (index(nm[j], nm[i] "/") == 1) { parent = 1; break }
      if (parent && st[i] != "fail") continue
      print st[i] "\t" nm[i]
    }
    n = 0
  }
  /^[ \t]*--- (PASS|FAIL|SKIP): / {
    line = $0; sub(/^[ \t]*--- /, "", line)
    s = substr(line, 1, 4); sub(/^[A-Z]+: /, "", line); sub(/ .*/, "", line)
    n++; nm[n] = line; st[n] = (s == "PASS") ? "pass" : (s == "FAIL") ? "fail" : "skip"
    next
  }
  /^(ok|FAIL|\?)[ \t]+[^ \t]/ { flush() }
  END { flush() }
' "$LOG" | report
finish $?
