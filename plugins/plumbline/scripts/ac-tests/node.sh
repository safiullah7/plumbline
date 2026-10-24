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
# Skipped and todo tests never count as passes, nor as fails. An expected
# failure (jest's test.failing, vitest's test.fails) that fails as expected
# counts as a pass: both runners report it exactly like a normal pass.
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
    if [[ "$runner" == jest ]]; then
      "$bin" --ci --json --outputFile="$OUT" -t "$re" 2>&1 | tr -d '\r' > "$LOG"
    else
      "$bin" run --reporter=json --outputFile="$OUT" -t "$re" 2>&1 | tr -d '\r' > "$LOG"
    fi
    # One "status<TAB>full name" line per test; a file that failed to run reports
    # as a fail under its path.
    node -e '
      let j;
      try { j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
      for (const f of j.testResults || []) {
        const rs = f.assertionResults || [];
        if (!rs.length && f.status === "failed") console.log("fail\t" + f.name);
        for (const a of rs) {
          const s = a.status === "passed" ? "pass" : a.status === "failed" ? "fail" : "skip";
          console.log(s + "\t" + [].concat(a.ancestorTitles || [], a.title).join(" "));
        }
      }' "$OUT" 2>/dev/null | tr -d '\r' | report
    finish $?
    ;;
  *)
    node --test --test-reporter=tap --test-name-pattern="$re" 2>&1 | tr -d '\r' > "$LOG"
    # TAP to "status<TAB>full name": a "# Subtest:" line names the test at its
    # depth; the matching "ok"/"not ok" line at the same depth closes it. Tests
    # with subtests only report their fails.
    awk '
      { match($0, /^ */); d = int(RLENGTH / 4); line = substr($0, RLENGTH + 1) }
      line ~ /^# Subtest: / {
        name[d] = substr(line, 12); child[d] = 0; if (d > 0) child[d - 1] = 1; next
      }
      line ~ /^(not )?ok [0-9]+/ {
        st = (line ~ /^not /) ? "fail" : "pass"
        if (toupper(line) ~ / # (SKIP|TODO)([^A-Z]|$)/) st = "skip"
        if (child[d] && st != "fail") next
        full = ""
        for (k = 0; k <= d; k++) full = full (k ? " " : "") name[k]
        print st "\t" full
      }' "$LOG" | report
    finish $?
    ;;
esac
