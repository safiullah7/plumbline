#!/usr/bin/env bash
# AC test adapter for Node: runs the tests named after the given AC IDs with the
# project's runner and reports each ID.
#   node.sh [--dir <path>] [--surface <s>] "AC-01-001|AC-01-002"
# The runner comes from the package.json in the run folder: vitest, then jest
# (dependencies, devDependencies or the test script), else node:test.
# Prints one line per ID: "AC-01-001: pass (2)", "AC-01-001: fail" or
# "AC-01-001: missing", then the runner's output tail when any ID isn't a pass.
# Exit 0 = every ID has a passing test and none failing; 1 = otherwise, or the
# runner isn't installed; 2 = usage.
#
# Rules: only leaf tests count (a describe/suite, or a test that only wraps
# subtests, adds nothing), and an ID counts when it appears anywhere in the
# test's full name (suite names included). A failing parent still counts as a fail.
# Skipped and todo tests never count as passes, nor as fails.
# Expected failures: a test is "xfail" (not a pass, not a fail) only when it
# failed as its marker said AND the marker's reason or the test's title names a
# finding ("finding #8", any case). node:test: `not ok ... # TODO <names a
# finding>`; the same marker on a test that passes (`ok ... # TODO <finding>`) is
# a fail, because the hole is closed. jest test.failing / vitest test.fails /
# `{ fails: true }` are read from the source, see below. Markers that don't name
# a finding (`{ todo: true }`, test.todo) behave as before; a jest test.failing or
# vitest test.fails that names none counts as skipped (it used to read as a pass,
# so a failing AC test wrapped in one could stand in for a passing test).
# PLUMBLINE_AC_ALL=1 (all-tests mode) drops -t / --test-name-pattern and runs
# everything; IDs are then optional (see common.sh for the counts line).
#
# Verified (Node 22.23, jest 29.7, vitest 3.2.4, Oct 2026):
# - node:test: `node --test --test-reporter=tap --test-name-pattern=<re>` with no
#   file arguments uses node's default discovery (*.test.*, *-test.*, *_test.*,
#   test-*, test.*, test/**; node_modules skipped). Non-matching tests aren't
#   reported. TAP lines: "ok N - name", "not ok N - name", directives
#   "# SKIP [reason]" and "# TODO [reason]" (also on "not ok"), each preceded by
#   "# Subtest: name"; nesting is 4 spaces per level. A suite whose name matches
#   runs all its tests. A file that fails to load reports as "not ok N - <path>".
# - jest: `jest --json --outputFile=<f> -t <re>`; vitest: `vitest run
#   --reporter=json --outputFile=<f> -t <re>`. Both write testResults[] with
#   assertionResults[] {status, ancestorTitles, title}; statuses passed, failed,
#   pending (jest skip and -t filtered), skipped (vitest), todo. A file's status
#   is "failed" when any test in it fails, so it is only used when the file has
#   no results (it failed to run).
# - test.failing (jest) and test.fails (vitest): one that fails is "passed" with
#   the same fields as a normal pass (no mode or flag in the JSON); one that
#   passes is "failed". So the JSON can't tell an expected failure from a pass.
#   Hence the source is read for a PASSED test: jest `--testLocationInResults`
#   and vitest `--includeTaskLocation` (a CLI flag in 3.2.4) both add
#   assertionResults[].location {line, column}, the line of the test( / test.fails(
#   call (the first line of a multi-line call; for .each, the line of the .each
#   call). The test's line must hold `.failing(`, `.fails(`, `.failing.each(`,
#   `.fails.each(` or `fails: true`; it is xfail when the title, that line or a
#   comment line just before it names a finding, else skip. If the line has no test( opener (the
#   location is the string argument), the line before is read too. With no
#   location, the line holding the test's title (only if exactly one does) or its
#   ID is used instead. A `fails: true` on a later line than the call isn't seen.
# - Name patterns are regexes (JS); [Aa][Cc] makes them case-insensitive in all three.
source "$(dirname "${0//\\//}")/../lib.sh"
NAME=node
usage() { echo "usage: $NAME.sh [--dir <path>] [--surface <s>] \"<AC IDs>\"" >&2; exit 2; }

source "$(dirname "${0//\\//}")/common.sh"   # arguments, IDs, run folder, report

# --- Runner ---
command -v node >/dev/null 2>&1 || { echo "$NAME: not installed"; exit 1; }
export NO_COLOR=1 FORCE_COLOR=0 CI=1

runner=$(node -e '
  let p = {};
  try { p = JSON.parse(require("fs").readFileSync("package.json", "utf8")); } catch (e) {}
  const d = Object.assign({}, p.dependencies, p.devDependencies);
  const t = (p.scripts && p.scripts.test) || "";
  console.log(d.vitest || /\bvitest\b/.test(t) ? "vitest" : d.jest || /\bjest\b/.test(t) ? "jest" : "node");
' 2>/dev/null | tr -d '\r')

# A local bin from the run folder upward, the way node resolves packages, so a
# workspace that hoists jest or vitest to the root still finds it.
local_bin() { # name
  local d="$run_dir"
  while [[ -n "$d" ]]; do
    [[ -x "$d/node_modules/.bin/$1" ]] && { printf '%s\n' "$d/node_modules/.bin/$1"; return 0; }
    [[ "$d" == */* ]] || break
    d="${d%/*}"
  done
  return 1
}

case "$runner" in
  jest|vitest)
    bin=$(local_bin "$runner") || { echo "$NAME: $runner: not installed"; exit 1; }
    t_args=(-t "$re")
    [[ "$ALL" == 1 ]] && t_args=()   # all-tests mode: no filter
    if [[ "$runner" == jest ]]; then
      "$bin" --ci --json --testLocationInResults --outputFile="$OUT" "${t_args[@]}" 2>&1 | tr -d '\r' > "$LOG"
    else
      "$bin" run --reporter=json --includeTaskLocation --outputFile="$OUT" "${t_args[@]}" 2>&1 | tr -d '\r' > "$LOG"
    fi
    # One "status<TAB>full name" line per test; a file that failed to run reports
    # as a fail under its path. Neither runner marks an expected failure in the JSON,
    # so a passed test whose title or comment/marker line names a finding has its
    # source read (see the header): .failing( / .fails( / fails: true -> xfail.
    node -e '
      const fs = require("fs");
      let j;
      try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
      const finding = /finding\s*#\d+/i;
      const marker = /\.(failing|fails)(\.each)?\s*[(`]|\bfails\s*:\s*true\b/;
      const opener = /\b(test|it)\b\s*[.(]/;
      const src = {};
      const lines = (f) => src[f] || (src[f] = (() => { try { return fs.readFileSync(f, "utf8").split(/\r?\n/); } catch (e) { return []; } })());
      const isComment = (l) => /^\s*(\/\/|\/\*|\*)/.test(l || "");
      // The lines to look at for one test: the one it starts on and the line before
      // (a comment, or the call when the location is the string argument). Returns
      // "named" (an expected-failure marker naming a finding), "plain" (a marker
      // naming none) or "" (no marker).
      function expected(f, a, full) {
        const L = lines(f.name);
        let at = a.location && a.location.line ? a.location.line - 1 : -1;
        if (at < 0 || at >= L.length) {
          // No location: the line holding the test title, else one holding its ID.
          const idm = full.toLowerCase().replace(/_/g, "-").match(/(ac|sec)-\d+-\d+/);
          const own = L.reduce((r, l, i) => (l.includes(a.title) ? r.concat(i) : r), []);
          const byId = L.reduce((r, l, i) => (idm && l.toLowerCase().replace(/_/g, "-").includes(idm[0]) ? r.concat(i) : r), []);
          at = own.length === 1 ? own[0] : byId.length ? byId[0] : -1;
          if (at < 0) return "";
        }
        const own = L[at] || "", prev = L[at - 1] || "";
        const prevCall = opener.test(prev) && !isComment(prev);
        const here = opener.test(own) ? own : own + " " + (prevCall ? "" : prev);
        if (!marker.test(here)) return "";
        const named = finding.test(full) || finding.test(own) || (isComment(prev) && finding.test(prev));
        if (named) return "named";
        // Unnamed: the method forms, or a fails: true before the test function (so a
        // one-line body holding { fails: true } is not taken for the option).
        return (/\.(failing|fails)(\.each)?\s*[(`]/.test(here) || /\bfails\s*:\s*true\b/.test(here.split("=>")[0])) ? "plain" : "";
      }
      for (const f of j.testResults || []) {
        const rs = f.assertionResults || [];
        if (!rs.length && f.status === "failed") console.log("fail\t" + f.name);
        for (const a of rs) {
          const full = [].concat(a.ancestorTitles || [], a.title).join(" ");
          let s = a.status === "passed" ? "pass" : a.status === "failed" ? "fail" : "skip";
          // A marked test reported passed failed as expected: xfail when the marker
          // names a finding, else skip (never a pass). One reported failed passed
          // (the runner fails it for that): naming a finding, its hole looks closed.
          if (s === "pass") { const k = expected(f, a, full); if (k === "named") s = "xfail"; else if (k === "plain") s = "skip"; }
          else if (s === "fail" && expected(f, a, full) === "named") s = "xpass";
          console.log(s + "\t" + full);
        }
      }' "$OUT" 2>/dev/null | tr -d '\r' | report
    finish $?
    ;;
  *)
    tp_args=(--test-name-pattern="$re")
    [[ "$ALL" == 1 ]] && tp_args=()   # all-tests mode: no filter
    node --test --test-reporter=tap "${tp_args[@]}" 2>&1 | tr -d '\r' > "$LOG"
    # TAP to "status<TAB>full name": a "# Subtest:" line names the test at its
    # depth; the matching "ok"/"not ok" line at the same depth closes it. Tests
    # with subtests only report their fails. "# TODO" naming a finding (in the
    # reason or the title): "not ok" is xfail, "ok" is a fail (the hole is closed).
    awk '
      { match($0, /^ */); d = int(RLENGTH / 4); line = substr($0, RLENGTH + 1) }
      line ~ /^# Subtest: / {
        name[d] = substr(line, 12); gsub(/\\#/, "#", name[d])   # TAP writes # in a name as \#
        child[d] = 0; if (d > 0) child[d - 1] = 1; next
      }
      line ~ /^(not )?ok [0-9]+/ {
        base = (line ~ /^not /) ? "fail" : "pass"; st = base
        if (toupper(line) ~ / # SKIP([^A-Z]|$)/) st = "skip"
        else if (toupper(line) ~ / # TODO([^A-Z]|$)/)
          st = (tolower(line) ~ /finding[ \t]*\\?#[0-9]+/) ? (base == "fail" ? "xfail" : "xpass") : "skip"   # TAP writes # as \#
        if (child[d] && !(st == "fail" && base == "fail")) next
        full = ""
        for (k = 0; k <= d; k++) full = full (k ? " " : "") name[k]
        print st "\t" full
      }' "$LOG" | report
    finish $?
    ;;
esac
