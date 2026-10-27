#!/usr/bin/env bash
# AC test adapter for Playwright Test: runs the e2e tests named after the given AC
# IDs and reports each ID.
#   playwright.sh [--dir <path>] [--surface <s>] "AC-01-001|AC-01-002"
# Runs `playwright test --grep <re> --reporter=json --retries=0` in the run
# folder, so the project's own config (projects, webServer, baseURL) applies.
# Prints one line per ID: "AC-01-001: pass (2)", "AC-01-001: fail" or
# "AC-01-001: missing", then the runner's output tail when any ID isn't a pass.
# Exit 0 = every ID has a passing test and none failing; 1 = otherwise, or
# Playwright isn't installed; 2 = usage.
#
# Rules: an ID counts when it appears anywhere in the test's full title
# (describe titles included, the file name isn't part of it). Skipped tests
# (test.skip, test.fixme, a skip in the body, not run after a serial failure),
# interrupted tests and tests marked test.fail never count as passes. Failed and
# timed-out tests are fails. --retries=0 overrides the config's retries, so a
# flaky test (one that passed only on a retry) fails here instead of passing.
# Each project of a multi-project config runs the test, and each run is counted.
#
# Verified (Node 22.23, @playwright/test 1.64.0, Oct 2026):
# - JSON (written to $PLAYWRIGHT_JSON_OUTPUT_NAME; the terminal then gets the
#   progress lines): {config, suites[], errors[], stats}. suites[] are files
#   (title = file name), nested suites are describes; a suite's specs[] have a
#   title and tests[] (one per project, with projectName) whose results[] hold one
#   entry per attempt {status, retry}. The spec title path is the file title, the
#   describe titles, then the spec title.
# - test.status is expected (ran as the test expects), unexpected (failed, timed
#   out, interrupted), flaky (failed, then passed on a retry) or skipped.
#   results[].status is passed, failed, timedOut, skipped or interrupted;
#   test.expectedStatus is passed (or failed for test.fail).
# - test.skip, test.fixme and test.skip(true) in the body: status skipped. A test
#   after a failure in a serial describe: skipped. A zero-test grep prints "No
#   tests found", exits 1 and still writes a JSON with empty suites.
# - --retries=0 beats `retries: 2` in the config: a test that passes only when
#   testInfo.retry > 0 comes back failed, with one result.
# - --grep also matches the file name, so a file called AC-01-001.spec.js is run;
#   its tests only count for an ID that is in their own title or a describe's.
source "$(dirname "${0//\\//}")/../lib.sh"
NAME=playwright
usage() { echo "usage: $NAME.sh [--dir <path>] [--surface <s>] \"<AC IDs>\"" >&2; exit 2; }

source "$(dirname "${0//\\//}")/common.sh"   # arguments, IDs, run folder, report

# --- Runner ---
command -v node >/dev/null 2>&1 || { echo "$NAME: not installed"; exit 1; }
export NO_COLOR=1 FORCE_COLOR=0 CI=1

# A local bin from the run folder upward, the way node resolves packages, so a
# workspace that hoists Playwright to the root still finds it.
local_bin() { # name
  local d="$run_dir"
  while [[ -n "$d" ]]; do
    [[ -x "$d/node_modules/.bin/$1" ]] && { printf '%s\n' "$d/node_modules/.bin/$1"; return 0; }
    [[ "$d" == */* ]] || break
    d="${d%/*}"
  done
  return 1
}
if bin=$(local_bin playwright); then
  runner=("$bin")
elif command -v npx >/dev/null 2>&1 && npx --no-install playwright --version >/dev/null 2>&1; then
  runner=(npx --no-install playwright)
else
  echo "$NAME: not installed"; exit 1
fi

PLAYWRIGHT_JSON_OUTPUT_NAME="$OUT" "${runner[@]}" test --grep "$re" --reporter=json --retries=0 2>&1 \
  | tr -d '\r' > "$LOG"
# One "status<TAB>full name" line per test. An older Playwright prints the JSON
# to stdout instead, so the log is the fallback when the file is empty.
node -e '
  const fs = require("fs");
  let j;
  for (const f of process.argv.slice(1)) {
    try { j = JSON.parse(fs.readFileSync(f, "utf8")); break; } catch (e) {}
  }
  if (!j) process.exit(0);
  const clean = (s) => String(s).replace(/\s+/g, " ").trim();
  function status(t) {
    const last = (t.results || []).slice(-1)[0] || {};
    if (t.status === "expected") return t.expectedStatus === "passed" ? "pass" : "skip";
    if (t.status === "unexpected") return last.status === "interrupted" ? "skip" : "fail";
    if (t.status === "flaky") return "fail";
    return "skip";
  }
  function walk(s, titles) {
    for (const sp of s.specs || []) {
      const name = clean(titles.concat(sp.title).join(" "));
      for (const t of sp.tests || []) console.log(status(t) + "\t" + name);
    }
    for (const c of s.suites || []) walk(c, titles.concat(c.title));
  }
  // The top-level suites are files: their title (the file name) is left out.
  for (const f of j.suites || []) walk(f, []);
' "$OUT" "$LOG" 2>/dev/null | tr -d '\r' | report
finish $?
