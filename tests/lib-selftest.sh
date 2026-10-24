#!/usr/bin/env bash
# Self-test for the v0.4 lib.sh helpers (feature_meta, module_dir,
# next_feature_number, run_checks) and ac-check.sh, on both docs layouts, plus
# parity between ac-check.sh and the task gate. Run from the repo root:
#   bash tests/lib-selftest.sh
# Works in bash on macOS and Linux, and in Git Bash on Windows.
set -u
command -v jq >/dev/null 2>&1 || { echo "jq isn't installed or isn't on PATH."; exit 1; }
G="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts"
REAL_NPM=$(command -v npm 2>/dev/null)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/.claude" "$T/bin" "$T/tmp" && cd "$T/repo"
export HOME="$T" CLAUDE_PROJECT_DIR="$T/repo" TMPDIR="$T/tmp"
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_DATA PLUMBLINE_HOOK_TIMING
unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC
source "$G/lib.sh"
R="$PROJECT_DIR"   # the repo root as lib.sh spells it

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
assert() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
eq() { # name, got, expected
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (got '$2', expected '$3')"; fi
}
has() { grep -qF -- "$2" <<<"$1"; }   # text, fixed string
current() { printf '%s\n' "$1" > "$T/repo/.claude/current-phase"; }
checks() { # typecheck, lint, AC tests: the three commands for the next case
  export PLUMBLINE_TYPECHECK="$1" PLUMBLINE_LINT="$2" PLUMBLINE_TEST_AC="$3"
}

# --- next_feature_number, module_dir and feature_meta on both layouts ---
eq "next number: no docs at all" "$(next_feature_number)" 01
mkdir -p docs/product/rooms
eq "next number: a module with no features" "$(next_feature_number)" 01
assert "module_dir: fails without an active feature" bash -c "! (source '$G/lib.sh'; module_dir)"

# Legacy layout: docs/product/<area>/phases/<phase>/, no .plumbline.
mkdir -p docs/product/demo/phases/phase-03
current docs/product/demo/phases/phase-03
eq "next number: legacy phase only" "$(next_feature_number)" 04
eq "module_dir: legacy layout is the area" "$(module_dir)" "$R/docs/product/demo"
eq "feature_meta: legacy profile defaults to full" "$(feature_meta profile)" full
eq "feature_meta: legacy ux defaults to yes" "$(feature_meta ux)" yes
eq "feature_meta: legacy module is the area" "$(feature_meta module)" demo
eq "feature_meta: legacy surfaces are empty" "$(feature_meta surfaces)" ""
out=$(feature_meta nonsense); rc=$?
assert "feature_meta: unknown key prints nothing, exit 0" test -z "$out" -a "$rc" = 0

# New layout, with a CRLF .plumbline carrying comments and padding.
F=docs/product/rooms/07-room-schedules; mkdir -p "$F"
printf '%s\r\n' '# feature metadata' 'module=rooms' 'number = 07' \
  'profile=standard        # quick is never stored' '  surfaces = api,web-ui  ' \
  'created=2026-10-24' > "$F/.plumbline"
current "$F"
eq "module_dir: new layout is the parent" "$(module_dir)" "$R/docs/product/rooms"
eq "feature_meta: profile, comment stripped" "$(feature_meta profile)" standard
eq "feature_meta: number, spaces trimmed" "$(feature_meta number)" 07
eq "feature_meta: surfaces, CRLF stripped" "$(feature_meta surfaces)" api,web-ui
eq "feature_meta: module" "$(feature_meta module)" rooms
eq "feature_meta: key missing from the file falls back" "$(feature_meta ux)" yes
eq "feature_meta: unknown key on a real file" "$(feature_meta nonsense)" ""
printf 'docs/product/rooms/07-room-schedules/\r\nignored line\r\n' > .claude/current-phase
eq "module_dir: CRLF current-phase with a trailing slash" "$(module_dir)" "$R/docs/product/rooms"
eq "feature_meta: same file through that spelling" "$(feature_meta profile)" standard

eq "next number: legacy phase-03 and 07-x" "$(next_feature_number)" 08
mkdir -p docs/product/billing/02-invoices docs/product/billing/09-refunds docs/product/rooms/contracts
echo x > docs/product/rooms/12-notes.md
eq "next number: across modules, 08/09 read as decimal, files ignored" "$(next_feature_number)" 10
mkdir -p docs/product/demo/phases/phase-11
eq "next number: a newer legacy phase wins" "$(next_feature_number)" 12

# --- run_checks: precedence, skips, failures and where it runs ---
checks true true 'f(){ [ "$1" = "AC-01-001|AC-01-002" ]; }; f'
run_checks "AC-01-001|AC-01-002"; rc=$?
eq "run_checks: env commands pass, IDs as one argument" "$rc/$RUN_CHECKS_FAILED" "0/"
assert "run_checks: timing names every check" \
  grep -qE '^typecheck [0-9]+s · lint [0-9]+s · tests [0-9]+s$' <<<"$RUN_CHECKS_TIMING"
assert "run_checks: log is a file" test -f "$RUN_CHECKS_LOG"
checks 'echo type-broke; false' true true
run_checks AC-01-001; rc=$?
eq "run_checks: typecheck failure" "$rc/$RUN_CHECKS_FAILED" "1/typecheck"
assert "run_checks: log holds the failing output" grep -q type-broke "$RUN_CHECKS_LOG"
checks true 'echo lint-broke; false' true
run_checks AC-01-001; rc=$?
eq "run_checks: lint failure" "$rc/$RUN_CHECKS_FAILED" "1/lint"
eq "run_checks: timing lists only the checks that passed" "${RUN_CHECKS_TIMING% *}" typecheck
checks true true false
run_checks AC-01-001; rc=$?
eq "run_checks: AC tests failure" "$rc/$RUN_CHECKS_FAILED" "1/tests"
run_checks ""; rc=$?
eq "run_checks: empty IDs skip the AC tests" "$rc/$RUN_CHECKS_FAILED" "0/"
assert "run_checks: no tests in the timing without IDs" test -n "${RUN_CHECKS_TIMING##*tests*}"
checks "" true true
run_checks AC-01-001; rc=$?
eq "run_checks: set-but-empty skips that check" "$rc/${RUN_CHECKS_TIMING%% *}" "0/lint"
checks "" "" ""
run_checks AC-01-001; rc=$?
eq "run_checks: everything skipped passes" "$rc/$RUN_CHECKS_TIMING" "0/"
checks 'test -f .claude/current-phase' true true
(cd "$T" && run_checks AC-01-001 && test "$(pwd)" = "$T"); rc=$?
eq "run_checks: runs in the repo root, caller's folder unchanged" "$rc" 0
run_checks AC-01-001 web-ui; rc=$?
eq "run_checks: surface argument accepted" "$rc" 0

# Defaults when the env vars are unset, through a stand-in npm that logs its
# arguments and fails the check named in FAKE_NPM_FAIL.
cat > "$T/bin/npm" <<'NPM'
#!/usr/bin/env bash
echo "$*" >> "$NPM_LOG"
[[ "$3" == "${FAKE_NPM_FAIL:-}" ]] && exit 1
exit 0
NPM
chmod +x "$T/bin/npm"
export NPM_LOG="$T/npm.log"
(
  unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC
  export PATH="$T/bin:$PATH"
  run_checks "AC-01-001|AC-01-002"; echo "rc=$?"
  export FAKE_NPM_FAIL=lint
  run_checks AC-01-001; echo "lint=$?/$RUN_CHECKS_FAILED"
  export PLUMBLINE_LINT=true
  run_checks AC-01-001; echo "override=$?"
) > "$T/defaults.out" 2>&1
out=$(cat "$T/defaults.out")
assert "run_checks: unset env vars use the npm defaults" has "$out" "rc=0"
eq "run_checks: default commands and arguments" "$(head -n3 "$NPM_LOG" | paste -sd';' -)" \
  "run -s typecheck;run -s lint;run -s test:ac -- AC-01-001|AC-01-002"
assert "run_checks: a failing default fails its check" has "$out" "lint=1/lint"
assert "run_checks: env var wins over the default" has "$out" "override=0"
eq "run_checks: overridden check doesn't run npm" "$(tail -n2 "$NPM_LOG" | paste -sd';' -)" \
  "run -s typecheck;run -s test:ac -- AC-01-001"

# The same defaults through the real npm and a package.json, when npm is installed.
if [[ -n "$REAL_NPM" ]]; then
  mkdir -p "$T/npmrepo"
  echo '{"name":"fixture","private":true,"scripts":{"typecheck":"exit 0","lint":"exit 0","test:ac":"echo"}}' \
    > "$T/npmrepo/package.json"
  out=$(unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC
        PROJECT_DIR=$(norm_path "$T/npmrepo"); run_checks AC-01-001; echo "rc=$?/$RUN_CHECKS_FAILED")
  eq "run_checks: real npm with package.json scripts" "$out" "rc=0/"
else
  echo "skip  run_checks: real npm case (npm isn't installed)"
fi

# --- ac-check.sh ---
ac() { bash "$G/ac-check.sh" "$@"; }
checks true true 'f(){ [ "$1" = "AC-01-001" ]; }; f'
out=$(ac AC-01-001 2>/dev/null); rc=$?
eq "ac-check: pass exits 0" "$rc" 0
assert "ac-check: pass line with timing" \
  grep -qE '^ac-check: pass \(typecheck [0-9]+s · lint [0-9]+s · tests [0-9]+s\)$' <<<"$out"
out=$(ac AC-01-001 --surface api 2>&1); rc=$?
eq "ac-check: --surface accepted" "$rc" 0
out=$(ac --surface=api "[AC-01-001] x" 2>&1); rc=$?
eq "ac-check: --surface=value and IDs inside text" "$rc" 0
checks true 'echo lint-broke; false' true
out=$(ac AC-01-001 2>&1 >/dev/null); rc=$?
eq "ac-check: lint failure exits 1" "$rc" 1
assert "ac-check: names the failed check" has "$out" "ac-check: lint failed"
assert "ac-check: shows the log on stderr" has "$out" "lint-broke"
checks true 'for i in $(seq 1 50); do echo "line $i"; done; false' true
out=$(ac AC-01-001 2>&1)
assert "ac-check: log tail is the last 30 lines" test "$(grep -c '^line ' <<<"$out")" = 30 -a -n "$(grep -x 'line 21' <<<"$out")"
checks true true 'f(){ [ "$1" = "AC-01-001" ]; }; f'
out=$(ac "AC-01-002|AC-01-001" 2>&1); rc=$?
eq "ac-check: missing tests exit 1" "$rc" 1
assert "ac-check: names the IDs whose tests failed" has "$out" "ac-check: tests for AC-01-001|AC-01-002 failed"
for a in "" "--bogus AC-01-001" "no ids here" "AC-01-001 --surface"; do
  ac $a >/dev/null 2>&1; rc=$?
  eq "ac-check: usage exit 2 for '${a}'" "$rc" 2
done
assert "ac-check: usage message" has "$(ac 2>&1)" "usage: ac-check.sh"
checks true true ""
out=$(ac AC-01-001 2>&1); rc=$?
eq "ac-check: an empty AC test command is refused, not a pass" "$rc/$out" "1/ac-check: no AC test command configured"
checks "" "" 'f(){ [ "$1" = "AC-01-001" ]; }; f'
out=$(ac AC-01-001 2>&1); rc=$?
eq "ac-check: empty typecheck and lint may still be skipped" "$rc" 0
assert "ac-check: ...and the timing names only the tests" grep -qE '^ac-check: pass \(tests [0-9]+s\)$' <<<"$out"
unset PLUMBLINE_TEST_AC
out=$(PLUMBLINE_TYPECHECK="" PLUMBLINE_LINT="" ac AC-01-001 2>&1 >/dev/null); rc=$?
assert "ac-check: unset AC test command falls back to the npm default (runs, not refused)" test -z "$(grep 'no AC test command' <<<"$out")"

# Without CLAUDE_PROJECT_DIR the root is the git root, else the current folder, so
# a Bash that has cd'd into apps/api still runs the checks at the root.
if command -v git >/dev/null 2>&1; then
  mkdir -p "$T/gitroot/apps/api" "$T/plain/sub"
  (cd "$T/gitroot" && git init -q) >/dev/null 2>&1
  touch "$T/gitroot/marker"
  root=$(norm_path "$T/gitroot")
  eq "project root: git root from a subfolder" \
    "$(cd "$T/gitroot/apps/api" && env -u CLAUDE_PROJECT_DIR bash -c 'source "$1/lib.sh"; echo "$PROJECT_DIR"' _ "$G")" "$root"
  checks 'test -f marker' 'test -f marker' 'f(){ test -f marker; }; f'
  out=$(cd "$T/gitroot/apps/api" && env -u CLAUDE_PROJECT_DIR bash "$G/ac-check.sh" AC-01-001 2>&1); rc=$?
  eq "project root: ac-check from a subfolder runs its checks at the git root" "$rc" 0
  eq "project root: a folder outside git is its own root" \
    "$(cd "$T/plain/sub" && env -u CLAUDE_PROJECT_DIR bash -c 'source "$1/lib.sh"; echo "$PROJECT_DIR"' _ "$G")" "$(norm_path "$T/plain/sub")"
  eq "project root: CLAUDE_PROJECT_DIR still wins" \
    "$(cd "$T/gitroot/apps/api" && CLAUDE_PROJECT_DIR="$T/plain" bash -c 'source "$1/lib.sh"; echo "$PROJECT_DIR"' _ "$G")" "$(norm_path "$T/plain")"
else
  echo "skip  project root fallback tests (git isn't installed)"
fi

# --- Parity: the task gate and ac-check.sh give the same verdict ---
current docs/product/rooms/07-room-schedules
printf '# 07 dev plan\r\n\r\nStatus: READY\r\n' > docs/product/rooms/07-room-schedules/dev-plan.md
task() { echo "{\"task_subject\":\"$1\",\"teammate_name\":\"eng-api\"}"; }
verdict() { # exit code, first stderr line
  case "$1/$2" in
    0/*) echo pass ;;
    */*typecheck\ failed*) echo typecheck ;;
    */*lint\ failed*) echo lint ;;
    */*tests\ for*) echo tests ;;
    *) echo "exit $1: $2" ;;
  esac
}
parity() { # name, subject, IDs, expected verdict, expected gate message
  local g a grc arc gv av
  g=$(task "$2" | bash "$G/task-completed-gate.sh" 2>&1 >/dev/null); grc=$?
  a=$(bash "$G/ac-check.sh" "$3" 2>&1 >/dev/null); arc=$?
  gv=$(verdict "$grc" "$(head -n1 <<<"$g")"); av=$(verdict "$arc" "$(head -n1 <<<"$a")")
  if [[ $grc -ne 0 && $grc -ne 2 ]] || [[ $arc -ne 0 && $arc -ne 1 ]]; then
    fail "parity: $1 (exit codes gate $grc, ac-check $arc)"
  elif [[ "$gv" != "$4" || "$av" != "$4" ]]; then
    fail "parity: $1 (gate '$gv', ac-check '$av', expected '$4')"
  elif [[ -n "$5" && "$(head -n1 <<<"$g")" != "$5" ]]; then
    fail "parity: $1 (gate said '$(head -n1 <<<"$g")')"
  else ok "parity: $1"; fi
}
checks true true 'f(){ [ "$1" = "AC-07-001" ]; }; f'
parity "all pass"         "[AC-07-001] x" AC-07-001 pass ""
parity "tests missing"    "[AC-07-002] x" AC-07-002 tests \
  "Task gate: tests for AC-07-002 failed or none exist. Name tests after their AC IDs."
checks true 'echo lint-broke; false' true
parity "lint fails"       "[AC-07-001] x" AC-07-001 lint "Task gate: lint failed."
checks 'echo type-broke; false' true true
parity "typecheck fails"  "[AC-07-001] x" AC-07-001 typecheck "Task gate: typecheck failed."
checks true true 'f(){ [ "$1" = "AC-07-001|AC-07-002" ]; }; f'
parity "two IDs, same order" "[AC-07-002][AC-07-001] x" "AC-07-002|AC-07-001" pass ""
checks true 'echo lint-broke; false' true
out=$(task "[AC-07-001] x" | bash "$G/task-completed-gate.sh" 2>&1)
assert "gate: log tail follows the message" test "$(sed -n 2p <<<"$out")" = lint-broke
checks true true false
out=$(task "[chore] Land contracts" | bash "$G/task-completed-gate.sh" 2>&1); rc=$?
eq "gate: [chore] skips the AC tests" "$rc/$out" "0/"
checks true true ""
out=$(task "[AC-07-001] x" | bash "$G/task-completed-gate.sh" 2>&1); rc=$?
eq "gate: an empty AC test command still skips the tests (v0.3)" "$rc/$out" "0/"
out=$(task "x" | bash "$G/task-completed-gate.sh" 2>&1); rc=$?
eq "gate: no AC IDs refused" "$rc/$out" \
  "2/Task gate: the task subject has no AC IDs. Ask the lead to prefix it, e.g. [AC-03-004]."
checks true true true
out=$(task "[AC-07-001] x" | PLUMBLINE_HOOK_TIMING=1 bash "$G/task-completed-gate.sh" 2>&1)
assert "gate: timing line when asked" \
  grep -qE '^Task gate passed: typecheck [0-9]+s · lint [0-9]+s · tests [0-9]+s$' <<<"$out"
before=$(ls -A "$T/tmp" | grep -c .)
checks true 'echo lint-broke; false' true
task "[AC-07-001] x" | bash "$G/task-completed-gate.sh" >/dev/null 2>&1
bash "$G/ac-check.sh" AC-07-001 >/dev/null 2>&1
checks true true true
bash "$G/ac-check.sh" AC-07-001 >/dev/null 2>&1
eq "gate and ac-check remove their logs" "$(ls -A "$T/tmp" | grep -c .)" "$before"

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
