#!/usr/bin/env bash
# AC test adapter for Go: runs the tests named after the given AC IDs and reports
# each ID.
#   go.sh [--dir <path>] [--surface <s>] "AC-01-001|AC-01-002"
# Runs `go test ./... -run '[Aa][Cc][-_]01[-_]001|...' -json` in the run folder.
# A test skipped with `t.Skip("xfail: finding #8 ...")` is "xfail" (not a pass, not
# a fail); other skips count as before. PLUMBLINE_AC_ALL=1 (all-tests mode) drops
# -run; IDs are then optional, and a package that fails with no failing test
# (it doesn't build) counts as one failed test.
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
# - -json prints one event per line: {"Action":"run|output|pass|fail|skip",
#   "Package":..,"Test":..,"Output":".."}. A test's last pass/fail/skip event is
#   its result (subtests are "Parent/sub"); events with no Test are the package's.
#   t.Skip's message arrives as an output event of that test. A package that
#   doesn't build gets a package-level fail and no test events. Events of
#   different packages may interleave. Cached results replay the same events.
source "$(dirname "${0//\\//}")/../lib.sh"
NAME=go
usage() { echo "usage: $NAME.sh [--dir <path>] [--surface <s>] \"<AC IDs>\"" >&2; exit 2; }

source "$(dirname "${0//\\//}")/common.sh"   # arguments, IDs, run folder, report

# --- Runner ---
command -v go >/dev/null 2>&1 || { echo "$NAME: not installed"; exit 1; }

run_args=(-run "$re")
[[ "$ALL" == 1 ]] && run_args=()   # all-tests mode: no filter
go test ./... "${run_args[@]}" -json 2>&1 | tr -d '\r' > "$OUT"
# The readable output for the tail: the Output of each event, unescaped, and any
# line that isn't JSON (a build error).
awk '
  function unesc(s) {
    gsub(/\\\\/, "\001", s); gsub(/\\n/, "\n", s); gsub(/\\t/, "\t", s); gsub(/\\r/, "", s)
    gsub(/\\"/, "\"", s); gsub(/\\u003c/, "<", s); gsub(/\\u003e/, ">", s); gsub(/\\u0026/, "\\&", s)
    gsub(/\001/, "\\", s); return s
  }
  /^\{/ { if ((p = index($0, "\"Output\":\"")) > 0) { s = substr($0, p + 10); sub(/"\}$/, "", s); printf "%s", unesc(s) } ; next }
  { print }
' "$OUT" > "$LOG"
# Events to "status<TAB>test name", one package at a time (two packages may use
# the same test name): a name with a "name/..." result in the same package is a
# parent, and only reports its fails. A skip whose output has "xfail: finding #n"
# is an expected failure (xfail). In all-tests mode a package that fails without a
# failing test (it doesn't build, or TestMain exits) is reported as one fail.
awk -v all="$ALL" '
  function field(s, k,   p, v) {
    p = index(s, "\"" k "\":\""); if (!p) return ""
    v = substr(s, p + length(k) + 4); sub(/".*/, "", v); return v
  }
  !/^\{/ { next }
  {
    act = field($0, "Action"); pkg = field($0, "Package"); t = field($0, "Test")
    if (!(pkg in seen)) { seen[pkg] = 1; pk[++np] = pkg }
    if (t == "") {
      if (act == "fail") pfail[pkg] = 1
      next
    }
    key = pkg SUBSEP t
    if (act == "output") {
      p = index($0, "\"Output\":\"")
      if (p) out[key] = out[key] substr($0, p + 10)
    } else if (act == "pass" || act == "fail" || act == "skip") {
      n++; kp[n] = pkg; nm[n] = t
      st[n] = (act == "pass") ? "pass" : (act == "fail") ? "fail" : "skip"
      if (act == "skip" && tolower(out[key]) ~ /xfail: finding[ \t]*#[0-9]+/) st[n] = "xfail"
      if (act == "fail") tfail[pkg] = 1
    }
  }
  END {
    for (q = 1; q <= np; q++) {
      pkg = pk[q]
      for (i = 1; i <= n; i++) {
        if (kp[i] != pkg) continue
        parent = 0
        for (j = 1; j <= n; j++)
          if (kp[j] == pkg && index(nm[j], nm[i] "/") == 1) { parent = 1; break }
        if (parent && st[i] != "fail") continue
        print st[i] "\t" nm[i]
      }
      if (all && pfail[pkg] && !tfail[pkg]) print "fail\t" pkg " (package failed)"
    }
  }
' "$OUT" | report
finish $?
