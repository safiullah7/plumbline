#!/usr/bin/env bash
# Runs every self-test suite and prints one line per suite, then a total.
#   bash tests/run-all.sh
# On Windows the hooks suite runs twice (TMPDIR unset, then TMPDIR set to the
# long-form temp folder), because Git Bash names that folder two ways and the
# path checks must treat both as the same place. Elsewhere it runs once.
# Exit 0 = every suite passed.
set -u
ROOT="$(cd "$(dirname "${0//\\//}")/.." && pwd)"
cd "$ROOT" || exit 1
LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
total_pass=0 total_fail=0 suites_failed=0

# report <label> <exit code> <pass> <fail>
report() {
  local status=PASS
  [[ "$2" -ne 0 || "$4" -ne 0 ]] && { status=FAIL; suites_failed=$((suites_failed + 1)); }
  printf '%-4s %-34s %s passed, %s failed\n' "$status" "$1" "$3" "$4"
  total_pass=$((total_pass + $3)); total_fail=$((total_fail + $4))
  [[ $status == FAIL ]] && tail -n 15 "$LOG" | sed 's/^/     /'
}

# run_sh <label> <script> [VAR=value ...]   (scripts end with "<n> passed, <n> failed")
run_sh() {
  local label="$1" script="$2" rc p f; shift 2
  env "$@" bash "$script" >"$LOG" 2>&1; rc=$?
  p=$(sed -n 's/^\([0-9][0-9]*\) passed, [0-9][0-9]* failed$/\1/p' "$LOG" | tail -n 1)
  f=$(sed -n 's/^[0-9][0-9]* passed, \([0-9][0-9]*\) failed$/\1/p' "$LOG" | tail -n 1)
  report "$label" "$rc" "${p:-0}" "${f:-1}"
}

windows=""
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) windows=1 ;; esac

for s in tests/*-selftest.sh; do
  name="${s##*/}"
  if [[ "$name" == hooks-selftest.sh && -n "$windows" ]]; then
    run_sh "$name (TMPDIR unset)" "$s" -u TMPDIR
    run_sh "$name (TMPDIR long form)" "$s" "TMPDIR=/c/Users/${USERNAME:-$USER}/AppData/Local/Temp"
  else
    run_sh "$name" "$s"
  fi
done

# visual-selftest.mjs prints "ok <name>" or "FAIL <name>" per check.
if command -v node >/dev/null 2>&1; then
  node tests/visual-selftest.mjs >"$LOG" 2>&1; rc=$?
  report "visual-selftest.mjs" "$rc" "$(grep -c '^ok ' "$LOG")" "$(grep -c '^FAIL ' "$LOG")"
else
  echo "skip visual-selftest.mjs (Node isn't installed)"
fi

echo "Total: $total_pass passed, $total_fail failed, $suites_failed suite(s) failed"
[[ $suites_failed -eq 0 ]]
