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
unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC PLUMBLINE_AC_ALL
export PLUMBLINE_REUSE=0   # a recorded pass never stands in for a run, except in the reuse cases below
export PLUMBLINE_TASK_CHECKS=full   # the task gate's default is tests-only; these cases assert its typecheck and lint
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
eq "ac-check: a pass with a silent test command prints only the pass line" "$(grep -c . <<<"$out")" 1
checks true true 'f(){ echo "generic: per-ID presence is not proven" >&2; echo noise; printf "AC-01-001: pass (2)\r\n"; echo "AC-01-002: pass (1)"; echo "  AC-01-003: indented"; }; f'
out=$(ac "AC-01-001|AC-01-002" 2>/dev/null); rc=$?
eq "ac-check: a pass shows the per-ID lines and the generic warning, pass line last" "$rc/$(sed 's/ (.*//' <<<"$out" | paste -sd';' -)" \
  "0/generic: per-ID presence is not proven;AC-01-001: pass;AC-01-002: pass;ac-check: pass"
checks true true 'f(){ [ "$1" = "AC-01-001" ]; }; f'
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
checks true true 'f(){ [ "$1" = "SEC-03-001" ]; }; f'
out=$(ac SEC-03-001 2>&1); rc=$?
eq "ac-check: a SEC-only call runs the tests" "$rc" 0
checks true true 'f(){ [ "$1" = "AC-03-001|SEC-03-001" ]; }; f'
out=$(ac "[AC-03-001 SEC-03-001] x" 2>&1); rc=$?
eq "ac-check: AC and SEC IDs in text reach the test command as one list" "$rc" 0
checks true true 'f(){ [ "$1" = "SEC-261028-01" ]; }; f'
out=$(ac SEC-261028-01 2>&1); rc=$?
eq "ac-check: a Quick SEC ID" "$rc" 0
checks true true 'f(){ [ "$1" = "SEC-03-001" ]; }; f'
out=$(ac "SEC-03-002|SEC-03-001" 2>&1); rc=$?
eq "ac-check: failing SEC tests exit 1" "$rc" 1
assert "ac-check: ...naming the SEC IDs" has "$out" "ac-check: tests for SEC-03-001|SEC-03-002 failed"
checks true true 'f(){ echo "SEC-05-001: fail"; for i in $(seq 1 40); do echo "runner $i"; done; false; }; f'
out=$(ac SEC-05-001 2>&1); rc=$?
assert "ac-check: a long failing log still shows the per-ID line" test "$rc" = 1 -a -n "$(grep -x 'SEC-05-001: fail' <<<"$out")"
checks true true 'f(){ echo "AC-05-001: fail"; echo "short log"; false; }; f'
out=$(ac AC-05-001 2>&1)
eq "ac-check: ...and a short one shows it once" "$(grep -c '^AC-05-001: fail$' <<<"$out")" 1
checks true true 'f(){ echo noise; echo "SEC-04-001: pass (2)"; printf "AC-04-001: pass (1)\r\n"; echo "  SEC-04-002: indented"; }; f'
out=$(ac "AC-04-001|SEC-04-001" 2>/dev/null)
eq "ac-check: a pass shows AC and SEC per-ID lines, pass line last" "$(sed 's/ (.*//' <<<"$out" | paste -sd';' -)" \
  "SEC-04-001: pass;AC-04-001: pass;ac-check: pass"
ac "SEC-03" >/dev/null 2>&1; rc=$?
eq "ac-check: a SEC prefix with one number is a usage error" "$rc" 2
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
# --tests-only: no typecheck, no lint, even ones the caller set (it empties both).
checks 'echo ran-typecheck >&2; false' 'echo ran-lint >&2; false' 'f(){ [ "$1" = "AC-01-001" ]; }; f'
out=$(ac AC-01-001 2>&1); rc=$?
eq "ac-check: a failing typecheck fails the run without --tests-only" "$rc" 1
out=$(ac --tests-only AC-01-001 2>&1); rc=$?
eq "ac-check: --tests-only skips a failing typecheck and lint" "$rc" 0
assert "ac-check: ...and the timing names only the tests" grep -qE '^ac-check: pass \(tests [0-9]+s\)$' <<<"$out"
assert "ac-check: ...and neither command ran" test -z "$(grep ran- <<<"$out")"
out=$(ac AC-01-001 --surface api --tests-only 2>&1); rc=$?
eq "ac-check: --tests-only after the IDs and --surface" "$rc" 0
checks true true 'echo ran-tests "$@" >&2; false'
out=$(ac --tests-only "AC-01-001|SEC-01-002" 2>&1); rc=$?
eq "ac-check: --tests-only still fails when the tests fail" "$rc" 1
assert "ac-check: ...naming the tests, with the IDs passed through" has "$out" "ac-check: tests for AC-01-001|SEC-01-002 failed"
eq "ac-check: --tests-only alone is a usage error" "$(ac --tests-only >/dev/null 2>&1; echo $?)" 2
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

# --- The surface's own checks: the task gate, ac-check.sh and make-briefs.sh ---
# A profile with several surfaces whose commands and stub adapters leave a trace,
# so each case can say which surface's commands ran.
unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC
export TRACE="$T/trace.log" NPM_LOG="$T/npm.log"
mkdir -p "$T/stubs"
for s in api web; do
  printf '#!/usr/bin/env bash\necho "%s-tests $*" >> "$TRACE"\n' "$s" > "$T/stubs/$s.sh"
done
row_api="| api | node | apps/api/** | npm start | echo api-typecheck >> \$TRACE | echo api-lint >> \$TRACE | bash $T/stubs/api.sh |"
row_web="| web-ui | node | apps/web/** | npm start | echo web-typecheck >> \$TRACE | echo web-lint >> \$TRACE | bash $T/stubs/web.sh |"
row_worker="| worker | node | apps/worker/** | npm start | echo worker-typecheck >> \$TRACE | echo worker-lint >> \$TRACE | |"
write_profile() { # surface rows (full table lines)
  { echo '# Project'; echo; echo '## Surfaces'
    echo '| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |'
    echo '| --- | --- | --- | --- | --- | --- | --- |'
    printf '%s\n' "$@"
  } > docs/product/project.md
}
write_profile "$row_api" "$row_web" "$row_worker"
P=docs/product/rooms/07-room-schedules
trace() { paste -sd';' - < "$TRACE"; }
npm_first() { head -n1 "$NPM_LOG"; }
gate_as() { # teammate, subject: runs the task gate with the stand-in npm first on PATH
  : > "$TRACE"; : > "$NPM_LOG"
  GATE_ERR=$(echo "{\"task_subject\":\"$2\",\"teammate_name\":\"$1\"}" \
    | PATH="$T/bin:$PATH" bash "$G/task-completed-gate.sh" 2>&1 >/dev/null)
  GATE_RC=$?
}
plan() { # the Team table's lines (header, separator, rows), as a CRLF plan
  { printf '# 07 dev plan\r\n\r\nStatus: READY\r\n\r\n## Team\r\n'; printf '%s\r\n' "$@"
    printf '\r\n## Ownership\r\n| Teammate | Owned globs |\r\n| --- | --- |\r\n'; } > "$P/dev-plan.md"
}
plan '| Teammate | Model | Workstream | Surface |' '| --- | --- | --- | --- |' \
  '| eng-api | sonnet | API | api |' '| eng-web | sonnet | UI | `web-ui` |' \
  '| eng-none | sonnet | Misc |  |' '| eng-x | sonnet | Misc | mobile |' '| eng-worker | sonnet | Jobs | worker |'
gate_as eng-api "[AC-07-001] x"
eq "gate: a 4-column Team table picks the teammate's surface" "$GATE_RC/$(trace)" \
  "0/api-typecheck;api-lint;api-tests AC-07-001"
gate_as eng-web "[AC-07-001][AC-07-002] x"
eq "gate: another teammate, another surface (backticks, CRLF plan)" "$GATE_RC/$(trace)" \
  "0/web-typecheck;web-lint;web-tests AC-07-001|AC-07-002"
gate_as eng-api "[chore] land contracts"
eq "gate: a [chore] runs the surface's typecheck and lint only" "$GATE_RC/$(trace)" \
  "0/api-typecheck;api-lint"
several="has no Surface in the dev plan's Team table and the profile lists several (api, web-ui, worker); ask the lead to add one, or tag coordination work [chore]"
gate_as eng-none "[AC-07-001] x"
eq "gate: an empty Surface cell and several profile rows is refused, nothing run" \
  "$GATE_RC/$(trace)/$(npm_first)/$GATE_ERR" "2///Task gate: eng-none $several"
gate_as eng-x "[AC-07-001] x"
eq "gate: a surface the profile doesn't list is refused, nothing run" "$GATE_RC/$(trace)/$(npm_first)/$GATE_ERR" \
  "2///Task gate: eng-x's Surface \"mobile\" in the dev plan's Team table isn't a surface in docs/product/project.md, which lists: api, web-ui, worker; ask the lead to fix one of them"
gate_as nobody "[AC-07-001] x"
eq "gate: another name with no Team row is checked as before (refused here: no surface)" \
  "$GATE_RC/$(trace)/$(npm_first)/$GATE_ERR" "2///Task gate: nobody $several"
gate_as lead "land contracts"
eq "gate: ...even with no AC IDs and no [chore] tag" "$GATE_RC/$(trace)/$(npm_first)/$GATE_ERR" "0///"
gate_as eng-none "[chore] land contracts"
eq "gate: a [chore] with no surface runs every surface's typecheck and lint" "$GATE_RC/$(trace)/$(npm_first)" \
  "0/api-typecheck;api-lint;web-typecheck;web-lint;worker-typecheck;worker-lint/"
: > "$TRACE"
out=$(echo '{"task_subject":"[chore] x","teammate_name":"eng-none"}' \
  | PLUMBLINE_LINT='! grep -q worker-typecheck "$TRACE"' bash "$G/task-completed-gate.sh" 2>&1); rc=$?
eq "gate: ...stopping at the first surface that fails, named" "$rc/$(head -n1 <<<"$out")" "2/Task gate: lint failed for surface worker."
out=$(echo '{"task_subject":"[chore] x","teammate_name":"eng-none"}' \
  | PLUMBLINE_HOOK_TIMING=1 bash "$G/task-completed-gate.sh" 2>&1)
assert "gate: ...and its timing line names each surface" \
  grep -qE '^Task gate passed: api: typecheck [0-9]+s · lint [0-9]+s · web-ui: .* · worker: typecheck' <<<"$out"
gate_as eng-worker "[AC-07-001] x"
eq "gate: a surface whose AC tests cell is empty fails the tests, before any check" \
  "$GATE_RC/$(trace)/$GATE_ERR" \
  "2//Task gate: AC tests: no command for surface worker in docs/product/project.md; write one (an adapter, generic, or a command), or none to skip"
gate_as eng-worker "[chore] x"
eq "gate: ...while its [chore] tasks still pass" "$GATE_RC/$(trace)" "0/worker-typecheck;worker-lint"
: > "$TRACE"
echo '{"task_subject":"[AC-07-001] x","teammate_name":"eng-worker"}' \
  | PLUMBLINE_TEST_AC="" bash "$G/task-completed-gate.sh" >/dev/null 2>&1; rc=$?
eq "gate: ...and PLUMBLINE_TEST_AC=\"\" still skips the tests (v0.3)" "$rc/$(trace)" "0/worker-typecheck;worker-lint"
: > "$TRACE"
echo '{"task_subject":"[AC-07-001] x","teammate_name":"eng-api"}' \
  | PLUMBLINE_LINT=true PLUMBLINE_TEST_AC='f(){ echo "env-tests $1" >> $TRACE; }; f' bash "$G/task-completed-gate.sh" >/dev/null 2>&1
eq "gate: env vars still override the surface's commands" "$(trace)" "api-typecheck;env-tests AC-07-001"
: > "$TRACE"
echo '{"task_subject":"[AC-07-001] x","teammate_name":"eng-api"}' \
  | PLUMBLINE_TYPECHECK=false bash "$G/task-completed-gate.sh" >/dev/null 2>&1; rc=$?
eq "gate: an env typecheck that fails refuses, with a surface too" "$rc/$(trace)" "2/"
plan '| Teammate | Model | Workstream |' '| --- | --- | --- |' '| eng-api | sonnet | API |'
gate_as eng-api "[AC-07-001] x"
eq "gate: a 3-column Team table and several profile rows is refused" \
  "$GATE_RC/$(trace)/$(npm_first)/$GATE_ERR" "2///Task gate: eng-api $several"
write_profile "$row_api"
gate_as eng-api "[AC-07-001] x"
eq "gate: a 3-column table and a one-row profile use that row, as before" \
  "$GATE_RC/$(trace)" "0/api-typecheck;api-lint;api-tests AC-07-001"
write_profile "$row_api" "| web-ui (check) | React | apps/web/** | | echo hint >> \$TRACE | | node |"
gate_as eng-api "[AC-07-001] x"
eq "gate: a (check) row is ignored, so the one confirmed row is still the only one" \
  "$GATE_RC/$(trace)" "0/api-typecheck;api-lint;api-tests AC-07-001"
rm -f docs/product/project.md
gate_as eng-api "[AC-07-001] x"
eq "gate: no profile keeps the npm defaults (v0.3)" "$GATE_RC/$(trace)/$(npm_first)" "0//run -s typecheck"
write_profile "$row_api" "$row_web" "$row_worker"
plan '| Teammate | Model | Workstream | Surface |' '| --- | --- | --- | --- |' '| eng-api | sonnet | API | web-ui |'
gate_as eng-api "[AC-07-001] x"
eq "gate: the plan's surface decides, not the profile's order" "$GATE_RC/$(trace)" \
  "0/web-typecheck;web-lint;web-tests AC-07-001"

# ac-check.sh --surface
acs() { : > "$TRACE"; : > "$NPM_LOG"; PATH="$T/bin:$PATH" bash "$G/ac-check.sh" "$@" 2>&1; }
out=$(acs AC-07-001 --surface api); rc=$?
eq "ac-check: --surface api runs api's commands" "$rc/$(trace)" "0/api-typecheck;api-lint;api-tests AC-07-001"
out=$(acs --surface=web-ui "AC-07-001|AC-07-002"); rc=$?
eq "ac-check: --surface=web-ui runs web's commands" "$rc/$(trace)" \
  "0/web-typecheck;web-lint;web-tests AC-07-001|AC-07-002"
for s in nope API "api, web-ui"; do
  out=$(acs AC-07-001 --surface "$s"); rc=$?
  eq "ac-check: unknown surface '$s' exits 2, nothing run" "$rc/$(trace)/$(npm_first)/$out" \
    "2///ac-check: unknown surface \"$s\"; the profile lists: api, web-ui, worker"
done
out=$(acs AC-07-001); rc=$?
eq "ac-check: no surface and several rows exits 2, nothing run" "$rc/$(trace)/$(npm_first)/$out" \
  "2///ac-check: several surfaces in docs/product/project.md; pass --surface <one of: api, web-ui, worker>"
out=$(PLUMBLINE_TEST_AC=true acs AC-07-001); rc=$?
eq "ac-check: ...also when only typecheck and lint come from the profile" "$rc/$(trace)" "2/"
# --all walks the feature's surfaces= (api,web-ui here); IDs belong to one surface,
# so with IDs and several surfaces it needs --surface.
out=$(acs --all AC-07-001); rc=$?
eq "ac-check --all: IDs, several surfaces and no --surface exits 2, nothing run" "$rc/$(trace)" "2/"
assert "ac-check --all: ...naming the surfaces" has "$out" "needs --surface <one of: api, web-ui>"
out=$(acs --all); rc=$?
assert "ac-check --all: without IDs it runs every surface of the feature in turn" test "$rc" = 0 -a -n "$(grep -x 'api-tests *' "$TRACE")" -a -n "$(grep -x 'web-tests *' "$TRACE")"
out=$(acs AC-07-001 --surface worker); rc=$?
eq "ac-check: a surface with an empty AC tests cell is refused" "$rc/$out" \
  "1/ac-check: AC tests: no command for surface worker in docs/product/project.md; write one (an adapter, generic, or a command), or none to skip"
eq "ac-check: ...before any check ran" "$(trace)" ""
write_profile "$row_api" "| jobs | node | apps/jobs/** | | echo jobs-typecheck >> \$TRACE | none | \`none\` |"
out=$(acs AC-07-001 --surface jobs); rc=$?
eq "ac-check: an AC tests cell of none is refused too" "$rc/$out/$(trace)" "1/ac-check: no AC test command configured/"
plan '| Teammate | Model | Workstream | Surface |' '| --- | --- | --- | --- |' '| eng-jobs | sonnet | Jobs | jobs |'
gate_as eng-jobs "[AC-07-001] x"
eq "gate: none skips the lint and AC tests cells on purpose" "$GATE_RC/$(trace)" "0/jobs-typecheck"
write_profile "$row_api" "$row_web" "$row_worker"
out=$(acs AC-07-001 --surface api); rc=$?
eq "ac-check: ...while another surface still passes" "$rc" 0
out=$(PLUMBLINE_TEST_AC='f(){ echo "env-tests $1" >> $TRACE; }; f' acs AC-07-001 --surface worker); rc=$?
eq "ac-check: the env var fills in a surface's empty AC tests cell" "$rc/$(trace)" "0/worker-typecheck;worker-lint;env-tests AC-07-001"

# A Team table with the lead's Effort column last (| Teammate | Model | Workstream |
# Surface | Effort |): both scripts read columns 1 and 4 only.
plan '| Teammate | Model | Workstream | Surface | Effort |' '| --- | --- | --- | --- | --- |' \
  '| eng-api | sonnet | API | api | medium |' '| eng-web | sonnet | UI | `web-ui` | high |' \
  '| eng-none | sonnet | Misc |  | low |'
gate_as eng-api "[AC-07-001] x"
eq "gate: a 5-column Team table (Effort last) picks the surface" "$GATE_RC/$(trace)" \
  "0/api-typecheck;api-lint;api-tests AC-07-001"
gate_as eng-web "[AC-07-001][AC-07-002] x"
eq "gate: ...for each teammate, backticks and all" "$GATE_RC/$(trace)" \
  "0/web-typecheck;web-lint;web-tests AC-07-001|AC-07-002"
gate_as eng-none "[AC-07-001] x"
eq "gate: ...and an empty Surface with the Effort filled is still refused" "$GATE_RC/$GATE_ERR" "2/Task gate: eng-none $several"

# make-briefs.sh
printf '%s\n' '| ID | Use case | Criterion |' '| --- | --- | --- |' '| AC-07-001 | UC-07-001 | one |' \
  '| AC-07-002 | UC-07-001 | two |' > "$P/acceptance-criteria.md"
mkbriefs() { # the Team table's lines
  { printf '# 07 dev plan\n\nStatus: READY\n\n## Team\n'; printf '%s\n' "$@"
    printf '\n## Ownership\n| Teammate | Owned globs |\n| --- | --- |\n| eng-api | apps/api/** |\n| eng-web | apps/web/** |\n'
    printf '\n## Tasks\n### eng-api\n- [AC-07-001] one (NORMAL)\n- [AC-07-002] two (NORMAL)\n### eng-web\n- [AC-07-001] ui (NORMAL)\n'
  } > "$P/dev-plan.md"
  rm -rf "$P/briefs"
  bash "$G/make-briefs.sh" 2>&1
}
out=$(mkbriefs '| Teammate | Model | Workstream | Surface |' '| --- | --- | --- | --- |' \
  '| eng-api | sonnet | API | api |' '| eng-web | sonnet | UI | web-ui |' '| eng-ghost | sonnet | UI | ghost |'); rc=$?
eq "make-briefs: a 4-column plan writes a brief per teammate" "$rc/$(grep -c 'briefs/' <<<"$out")" "0/3"
b=$(cat "$P/briefs/eng-api.md")
assert "make-briefs: the brief names the surface" has "$b" "Surface: api"
assert "make-briefs: ...and its typecheck cell" has "$b" 'Typecheck: echo api-typecheck >> $TRACE'
assert "make-briefs: ...and its AC tests cell" has "$b" "AC tests: bash $T/stubs/api.sh"
assert "make-briefs: ...and the ac-check line with its task IDs and surface" \
  has "$b" 'ac-check.sh" "AC-07-001|AC-07-002" --surface api'
assert "make-briefs: ...from the scripts folder named in context, not a machine path" has "$b" 'bash "<scripts>/ac-check.sh"'
assert "make-briefs: the other surface's commands stay out" test -z "$(grep web- <<<"$b")"
assert "make-briefs: the core lists the tasks, one line each, with label, IDs, rating and file" \
  has "$b" "- T2 [AC-07-002] two (NORMAL): $P/briefs/eng-api/T2.md"
assert "make-briefs: the AC rows moved to the task's file" \
  test -z "$(grep '| AC-07-002 |' <<<"$b")" -a -n "$(grep '| AC-07-002 |' "$P/briefs/eng-api/T2.md")"
assert "make-briefs: ...which has only that task's rows" test -z "$(grep '| AC-07-001 |' "$P/briefs/eng-api/T2.md")"
assert "make-briefs: ...and the tests-only ac-check line with the task's IDs and surface" \
  has "$(cat "$P/briefs/eng-api/T2.md")" 'ac-check.sh" --tests-only "AC-07-002" --surface api'
assert "make-briefs: the second brief has its own surface" has "$(cat "$P/briefs/eng-web.md")" "--surface web-ui"
b=$(cat "$P/briefs/eng-ghost.md")
assert "make-briefs: a surface with no profile row is named, without commands" \
  test -n "$(grep -x 'Surface: ghost' <<<"$b")" -a -z "$(grep -E 'Typecheck:|ac-check' <<<"$b")"
out=$(mkbriefs '| Teammate | Model | Workstream |' '| --- | --- | --- |' '| eng-api | sonnet | API |'); rc=$?
b=$(cat "$P/briefs/eng-api.md")
eq "make-briefs: a 3-column plan still works" "$rc/$(grep -c 'briefs/' <<<"$out")" "0/1"
assert "make-briefs: ...with no surface section" test -z "$(grep -E 'Your surface|ac-check' <<<"$b")"
assert "make-briefs: ...and its tasks" has "$b" "- T2 [AC-07-002] two (NORMAL)"
assert "make-briefs: ...whose files have no ac-check line either" \
  test -f "$P/briefs/eng-api/T2.md" -a -z "$(grep ac-check "$P"/briefs/eng-api/*.md)"
out=$(mkbriefs '| Teammate | Model | Workstream | Surface |' '| --- | --- | --- | --- |' '| eng-api | sonnet | API |  |'); rc=$?
assert "make-briefs: an empty Surface cell gives no surface section" \
  test "$rc" = 0 -a -z "$(grep 'Your surface' "$P/briefs/eng-api.md")"
out=$(mkbriefs '| Teammate | Model | Workstream | Surface | Effort |' '| --- | --- | --- | --- | --- |' \
  '| eng-api | sonnet | API | api | medium |' '| eng-web | sonnet | UI | `web-ui` | high |'); rc=$?
b=$(cat "$P/briefs/eng-api.md")
eq "make-briefs: a 5-column plan (Effort last) writes a brief per teammate" "$rc/$(grep -c 'briefs/' <<<"$out")" "0/2"
assert "make-briefs: ...with the surface from column 4" has "$b" "Surface: api"
assert "make-briefs: ...its AC tests cell" has "$b" "AC tests: bash $T/stubs/api.sh"
assert "make-briefs: ...and the Effort value isn't taken for the surface" test -z "$(grep -E 'Surface: medium' <<<"$b")"
assert "make-briefs: ...the second brief has its own surface" has "$(cat "$P/briefs/eng-web.md")" "--surface web-ui"

# --- Expected failures: run_checks reads the adapters' xfail-only trailer (v0.6.2) ---
current docs/product/rooms/07-room-schedules
S07=docs/product/rooms/07-room-schedules/security.md
write_sec07() { # own attack rows, findings rows (one per line)
  { printf '# Feature 07 security\n\nIndependent pass: not needed\n\n## Own attacks\n| SEC ID | Surface | Attack | Must happen |\n| --- | --- | --- | --- |\n%s\n\n' "$1"
    printf '## Findings\n| # | Severity | Finding | Status | Evidence |\n| --- | --- | --- | --- | --- |\n%s\n' "$2"; } > "$S07"
}
write_sec07 '| SEC-07-001 | api | a | b |'$'\n''| SEC-07-002 | api | a | b |'$'\n''| SEC-07-003 | api | a | b |' \
  '| 1 | medium | Replay | deferred | SEC-07-001 |'$'\n''| 2 | low | Other | verified | SEC-07-002 |'$'\n''| 3 | high | Open one | open | SEC-07-003 |'
eq "security_covered_ids: a deferred medium finding covers its own attack, a verified or open-high one doesn't" "$(security_covered_ids | paste -sd' ' -)" "SEC-07-001"
checks true true 'f(){ echo "SEC-07-001: xfail"; echo "ac-tests: xfail only: SEC-07-001"; return 1; }; f'
run_checks SEC-07-001; rc=$?
eq "run_checks: a test run whose only problem is a covered xfail passes" "$rc/$RUN_CHECKS_FAILED" "0/"
assert "run_checks: ...keeping the per-ID line in the log" grep -qx 'SEC-07-001: xfail' "$RUN_CHECKS_LOG"
assert "run_checks: ...and the tests in the timing" grep -qE 'tests [0-9]+s$' <<<"$RUN_CHECKS_TIMING"
checks true true 'f(){ echo "SEC-07-002: xfail"; echo "ac-tests: xfail only: SEC-07-002"; return 1; }; f'
run_checks SEC-07-002; rc=$?
eq "run_checks: an xfail under a verified finding fails" "$rc/$RUN_CHECKS_FAILED" "1/tests"
eq "run_checks: ...with the hint naming the ID" "$RUN_CHECKS_ERROR" "only an own attack under a deferred or accepted finding may be an expected failure: SEC-07-002"
checks true true 'f(){ echo "AC-07-001: xfail"; echo "ac-tests: xfail only: AC-07-001"; return 1; }; f'
run_checks AC-07-001; rc=$?
eq "run_checks: an xfail on an AC ID fails" "$rc/$RUN_CHECKS_FAILED" "1/tests"
checks true true 'f(){ echo "ac-tests: xfail only: SEC-07-001 AC-07-001 SEC-07-003"; return 1; }; f'
run_checks "SEC-07-001|AC-07-001"; rc=$?
eq "run_checks: one uncovered ID in the trailer fails the step, naming only the uncovered" "$rc/${RUN_CHECKS_ERROR##*: }" "1/AC-07-001 SEC-07-003"
checks true true 'echo "SEC-07-001: fail"; exit 1'
run_checks SEC-07-001; rc=$?
eq "run_checks: a plain failure with no trailer stays a failure, with no hint" "$rc/$RUN_CHECKS_FAILED/$RUN_CHECKS_ERROR" "1/tests/"
# Only the adapter's own trailer counts: a trailer a test printed into the output is ignored.
checks true true 'f(){ echo "AC-07-009: fail"; echo "--- pytest output (last 40 lines) ---"; echo "ac-tests: xfail only: SEC-07-001"; return 1; }; f'
run_checks "AC-07-009"; rc=$?
eq "run_checks: a trailer inside a failing run's output tail is ignored" "$rc/$RUN_CHECKS_FAILED" "1/tests"
checks true true 'f(){ echo "SEC-07-001: xfail"; echo "ac-tests: xfail only: SEC-07-001"; echo "more output"; return 1; }; f'
run_checks SEC-07-001; rc=$?
eq "run_checks: ...and so is one that isn't the last line" "$rc/$RUN_CHECKS_FAILED" "1/tests"
checks true true 'f(){ echo "SEC-07-001: xfail"; echo "AC-07-009: missing"; echo "ac-tests: xfail only: SEC-07-001"; return 1; }; f'
run_checks "SEC-07-001|AC-07-009"; rc=$?
eq "run_checks: ...or one after a missing ID" "$rc/$RUN_CHECKS_FAILED" "1/tests"
checks true true 'f(){ echo "ac-tests: counts 1 0 1 0 0"; echo "ac-tests: failed: a broken test"; echo "ac-tests: xfail only: SEC-07-001"; return 1; }; f'
run_checks "SEC-07-001"; rc=$?
eq "run_checks: ...or one after a failed test in all-tests output" "$rc/$RUN_CHECKS_FAILED" "1/tests"
# The task gate agrees with run_checks (hooks-selftest has the hook-level cases).
checks true true 'f(){ echo "SEC-07-001: xfail"; echo "ac-tests: xfail only: SEC-07-001"; return 1; }; f'
out=$(bash "$G/ac-check.sh" SEC-07-001 2>&1); rc=$?
eq "ac-check: a covered xfail passes, with the per-ID line, the trailer and the pass line" "$rc/$(grep -c . <<<"$out")" "0/3"
assert "ac-check: ...the per-ID line is the adapter's" has "$out" "SEC-07-001: xfail"
checks true true 'f(){ echo "AC-07-001: xfail"; echo "ac-tests: xfail only: AC-07-001"; return 1; }; f'
out=$(bash "$G/ac-check.sh" AC-07-001 2>&1); rc=$?
eq "ac-check: an uncovered xfail fails" "$rc" 1
assert "ac-check: ...and says why" has "$out" "only an own attack under a deferred or accepted finding may be an expected failure: AC-07-001"
rm -f "$S07"

# --- All-tests mode: run_checks with PLUMBLINE_AC_ALL=1 ---
mkdir -p "$T/fake/ac-tests"
cat > "$T/fake/ac-tests/fake.sh" <<'EOF'
#!/usr/bin/env bash
# A stand-in adapter (its path has /ac-tests/): the per-ID lines for the IDs given, then
# the counts line. FAKE_MISSING lists IDs that print missing, FAKE_FAIL=1 exits 1,
# FAKE_COMMIT=1 commits mid-run, FAKE_COUNTS overrides the counts. Each run is logged.
echo "run args=$# all=${PLUMBLINE_AC_ALL:-}" >> "$FAKE_LOG"
rc=0
for id in ${1//|/ }; do
  if [[ " ${FAKE_MISSING:-} " == *" $id "* ]]; then echo "$id: missing"; rc=1
  elif [[ " ${FAKE_XFAIL:-} " == *" $id "* ]]; then echo "$id: xfail"
  else echo "$id: pass (1)"; fi
done
echo "ac-tests: counts ${FAKE_COUNTS:-5 1 0 2 3}"
[[ -n "${FAKE_XFAIL:-}" && $rc == 0 ]] && { echo "ac-tests: xfail only: $FAKE_XFAIL"; rc=1; }
[[ "${FAKE_FAIL:-}" == 1 ]] && { echo "ac-tests: failed: the broken test"; rc=1; }
[[ "${FAKE_COMMIT:-}" == 1 ]] && git -C "$CLAUDE_PROJECT_DIR" commit -q --allow-empty -m "moved during the run"
exit $rc
EOF
export FAKE_LOG="$T/fake.log"; : > "$FAKE_LOG"
FAKE="bash $T/fake/ac-tests/fake.sh"
checks true true "$FAKE"
run_checks ""; rc=$?
eq "run_checks: empty IDs skip the tests outside all-tests mode" "$rc/$(wc -l < "$FAKE_LOG" | tr -d ' ')" "0/0"
(export PLUMBLINE_AC_ALL=1; run_checks ""; echo "$? ${RUN_CHECKS_TIMING}") > "$T/all.out"
assert "run_checks: all-tests mode runs the tests with empty IDs, passing no argument" test "$(tail -n1 "$FAKE_LOG")" = "run args=0 all=1"
assert "run_checks: ...and times them" grep -qE '^0 typecheck [0-9]+s · lint [0-9]+s · tests [0-9]+s$' "$T/all.out"
(export PLUMBLINE_AC_ALL=1; run_checks "AC-01-001|AC-01-002"; echo "$?")  > "$T/all.out"
eq "run_checks: all-tests mode with IDs hands them to the adapter" "$(tail -n1 "$FAKE_LOG")" "run args=1 all=1"
checks true true 'f(){ [ $# -eq 0 ]; }; f'
(export PLUMBLINE_AC_ALL=1; run_checks "AC-01-001"; echo "$?/$(grep -c 'warning' "$RUN_CHECKS_LOG")") > "$T/all.out"
eq "run_checks: a raw command in all-tests mode runs with no IDs, after a warning" "$(cat "$T/all.out")" "0/1"
checks true true 'false'
(export PLUMBLINE_AC_ALL=1; run_checks ""; echo "$?/$RUN_CHECKS_FAILED") > "$T/all.out"
eq "run_checks: ...and is judged by its exit status" "$(cat "$T/all.out")" "1/tests"
checks true true ""
(export PLUMBLINE_AC_ALL=1; run_checks ""; echo "$?/$RUN_CHECKS_TIMING") > "$T/all.out"
eq "run_checks: a none AC tests cell runs typecheck and lint only" "$(sed -E 's/ [0-9]+s/ Ns/g' "$T/all.out")" "0/typecheck Ns · lint Ns"
unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC

# --- ac-check --all: the summary, per-ID results and the reuse of a full pass ---
RR="$T/rr"; mkdir -p "$RR/src" "$RR/docs/product/m/01-x/qa" "$RR/docs/product/m/01-x/contracts"
(cd "$RR" && git init -q && git config user.email t@t && git config user.name t && git config core.autocrlf false \
  && echo 'one' > src/a.js && echo 'spec v1' > docs/product/m/01-x/spec.md && echo 'shot' > docs/product/m/01-x/qa/shot.txt \
  && echo 'contract v1' > docs/product/m/01-x/contracts/api.md && git add -A && git commit -q -m first) >/dev/null 2>&1
aa() { (cd "$RR" && CLAUDE_PROJECT_DIR="$RR" bash "$G/ac-check.sh" "$@"); }   # stdout and stderr both reach the caller
fakeruns() { wc -l < "$FAKE_LOG" | tr -d ' '; }
recs() { local f="$RR/.git/plumbline/checks.tsv"; if [[ -f "$f" ]]; then wc -l < "$f" | tr -d ' '; else echo 0; fi; }
export PLUMBLINE_TYPECHECK=true PLUMBLINE_LINT=true PLUMBLINE_TEST_AC="$FAKE" PLUMBLINE_REUSE=0
: > "$FAKE_LOG"
out=$(aa --all AC-01-001 2>&1); rc=$?
eq "ac-check --all: a pass exits 0" "$rc" 0
assert "ac-check --all: the summary line from the counts" grep -qE '^ac-check: all tests on default: 5 passed, 1 expected failure, 0 failed, 2 skipped \(3 without an ID\) in [0-9]+m [0-9]+s$' <<<"$out"
assert "ac-check --all: the adapter's per-ID and counts lines are shown" test -n "$(grep -x 'AC-01-001: pass (1)' <<<"$out")" -a -n "$(grep -x 'ac-tests: counts 5 1 0 2 3' <<<"$out")"
eq "ac-check --all: the adapter got PLUMBLINE_AC_ALL=1 and the IDs" "$(tail -n1 "$FAKE_LOG")" "run args=1 all=1"
out=$(aa --all 2>&1); rc=$?
eq "ac-check --all: IDs are optional" "$rc/$(tail -n1 "$FAKE_LOG")" "0/run args=0 all=1"
out=$(FAKE_MISSING=AC-01-002 aa --all "AC-01-001|AC-01-002" 2>&1); rc=$?
eq "ac-check --all: a missing ID fails the run" "$rc" 1
assert "ac-check --all: ...naming it" has "$out" "AC-01-002: missing"
assert "ac-check --all: ...and saying which tests failed" has "$out" "ac-check: tests for AC-01-001|AC-01-002 failed"
out=$(FAKE_FAIL=1 aa --all 2>&1)
assert "ac-check --all: with no IDs it says all tests failed" has "$out" "ac-check: all tests failed"
out=$(FAKE_FAIL=1 aa --all 2>&1); rc=$?
eq "ac-check --all: a failing suite exits 1" "$rc" 1
assert "ac-check --all: ...and the failed test is named" has "$out" "ac-tests: failed: the broken test"
out=$(PLUMBLINE_TEST_AC='true' aa --all 2>&1); rc=$?
eq "ac-check --all: a raw command passes by exit status, with the warning" "$rc/$(grep -c 'warning' <<<"$out")" "0/1"
assert "ac-check --all: ...and the summary says the counts are unknown" has "$out" "counts unknown (generic)"
out=$(PLUMBLINE_TEST_AC='' aa --all 2>&1); rc=$?
eq "ac-check --all: a none AC tests command runs typecheck and lint only" "$rc" 0
assert "ac-check --all: ...and says so" has "$out" "skipped"
out=$(PLUMBLINE_TEST_AC='' aa AC-01-001 2>&1); rc=$?
eq "ac-check: without --all an empty AC test command is still refused" "$rc" 1
aa --fresh >/dev/null 2>&1; rc=$?
eq "ac-check: --fresh without --all or IDs is a usage error" "$rc" 2
eq "ac-check: nothing was recorded with PLUMBLINE_REUSE=0" "$(recs)" 0

# Reuse (PLUMBLINE_REUSE unset again): only --all records and reuses.
unset PLUMBLINE_REUSE
: > "$FAKE_LOG"
aa AC-01-001 >/dev/null 2>&1
eq "reuse: a plain ac-check run records nothing" "$(recs)" 0
out=$(aa --all "AC-01-001" 2>&1); rc=$?
eq "reuse: a first --all pass runs the tests and records one line" "$rc/$(fakeruns)/$(recs)" "0/2/1"
rec=$(cat "$RR/.git/plumbline/checks.tsv")
eq "reuse: the record has eight tab-separated fields" "$(awk -F'\t' '{ print NF }' <<<"$rec")" 8
eq "reuse: ...surface, per-ID results, sha and no expected failures" "$(awk -F'\t' '{ print $2 "/" $4 "/" $5 "/" $8 }' <<<"$rec")" "default/AC-01-001=pass/$(git -C "$RR" rev-parse --short=7 HEAD)/-"
before=$(fakeruns)
out=$(aa --all AC-01-001 2>&1); rc=$?
eq "reuse: the same --all at the same code is reused, nothing runs" "$rc/$(fakeruns)" "0/$before"
assert "reuse: ...with the reusing line and the per-ID line" grep -qE '^ac-check: reusing the full pass from [0-9a-f]{7} \([0-9]+s ago\)$' <<<"$out"
assert "reuse: ...and AC-01-001: pass" has "$out" "AC-01-001: pass"
out=$(aa --all 2>&1); rc=$?
eq "reuse: an --all with no IDs is a subset too" "$rc/$(fakeruns)" "0/$before"
out=$(aa --all AC-01-009 2>&1); rc=$?
assert "reuse: an ID the pass didn't cover runs the tests" test "$rc" = 0 -a "$(fakeruns)" = $((before + 1))
before=$(fakeruns)
out=$(aa --all AC-01-001 --fresh 2>&1)
eq "reuse: --fresh runs again" "$(fakeruns)" "$((before + 1))"
before=$(fakeruns); n=$(recs)
out=$(PLUMBLINE_REUSE=0 aa --all AC-01-001 2>&1)
eq "reuse: PLUMBLINE_REUSE=0 runs again, and records nothing" "$(fakeruns)/$(recs)" "$((before + 1))/$n"
before=$(fakeruns)
out=$(PLUMBLINE_LINT='true ' aa --all AC-01-001 2>&1)
eq "reuse: a changed command isn't reused" "$(fakeruns)" "$((before + 1))"
# Plumbline's own documents are not part of the code.
echo 'spec v2' >> "$RR/docs/product/m/01-x/spec.md"; echo 'more' >> "$RR/docs/product/m/01-x/qa/shot.txt"; echo new > "$RR/docs/product/m/01-x/notes.md"
before=$(fakeruns); out=$(aa --all AC-01-001 2>&1)
eq "reuse: uncommitted changes to docs/product documents and qa/ don't stop it" "$(fakeruns)" "$before"
git -C "$RR" add -A && git -C "$RR" commit -q -m "docs only"
out=$(aa --all AC-01-001 2>&1)
eq "reuse: ...nor a commit that changes only them" "$(fakeruns)" "$before"
assert "reuse: ...it still says reusing" has "$out" "reusing the full pass"
echo 'contract v2' > "$RR/docs/product/m/01-x/contracts/api.md"; git -C "$RR" add -A && git -C "$RR" commit -q -m "contract"
out=$(aa --all AC-01-001 2>&1)
eq "reuse: a contracts/ change is code, no reuse" "$(fakeruns)" "$((before + 1))"
before=$(fakeruns)
echo 'two' > "$RR/src/a.js"; git -C "$RR" add -A && git -C "$RR" commit -q -m "code"
out=$(aa --all AC-01-001 2>&1)
eq "reuse: a code commit, no reuse" "$(fakeruns)" "$((before + 1))"
before=$(fakeruns); n=$(recs)
echo 'three' > "$RR/src/a.js"
out=$(aa --all AC-01-001 2>&1)
eq "reuse: uncommitted code, no reuse" "$(fakeruns)" "$((before + 1))"
eq "reuse: ...and the pass isn't recorded" "$(recs)" "$n"
git -C "$RR" add -A && git -C "$RR" commit -q -m "code 3"
before=$(fakeruns)
out=$(FAKE_FAIL=1 aa --all AC-01-001 2>&1); rc=$?
n=$(recs)
out=$(FAKE_FAIL=1 aa --all AC-01-001 2>&1)
eq "reuse: a failure is never recorded or reused (it runs both times)" "$rc/$(fakeruns)" "1/$((before + 2))"
out=$(aa --all AC-01-001 2>&1); rc=$?
eq "reuse: ...so the next pass runs and is recorded" "$rc/$(fakeruns)/$(recs)" "0/$((before + 3))/$((n + 1))"
n=$(recs); before=$(fakeruns)
out=$(FAKE_COMMIT=1 aa --all AC-01-001 --fresh 2>&1); rc=$?
eq "reuse: a run during which HEAD moved passes but isn't recorded" "$rc/$(recs)" "0/$n"
out=$(aa --all AC-01-001 2>&1)
eq "reuse: ...and the new HEAD (an empty commit, same tree) is the same code, so the earlier pass is reused" "$(fakeruns)" "$((before + 1))"
# 20 records at most.
for i in $(seq 1 22); do echo "$i" > "$RR/src/a.js"; git -C "$RR" add -A; git -C "$RR" commit -q -m "c$i"; aa --all AC-01-001 >/dev/null 2>&1; done
eq "reuse: the record keeps the last 20 lines" "$(recs)" 20
# An expected failure is recorded and reused as xfail, and only while a deferred or
# accepted finding still covers it (security.md is a document, outside the code key).
F1="$RR/docs/product/m/01-x"
printf 'security=attacks\n' > "$F1/.plumbline"
cat > "$F1/security.md" <<'EOF'
# Security

## Own attacks
| SEC ID | Surface | Attack | Must happen |
| --- | --- | --- | --- |
| SEC-01-005 | api | a huge description | 400 |

## Findings
| # | Severity | Finding | Status | Evidence |
| --- | --- | --- | --- | --- |
| 1 | low | description has no length limit | deferred | SEC-01-005: fail, got 201 |
EOF
git -C "$RR" add -A && git -C "$RR" commit -q -m "a deferred finding"
before=$(fakeruns)
out=$(FAKE_XFAIL=SEC-01-005 aa --all "AC-01-001|SEC-01-005" 2>&1); rc=$?
eq "reuse: a covered xfail run passes and is recorded" "$rc/$(fakeruns)" "0/$((before + 1))"
eq "reuse: ...with each ID's result and the run's expected failures" "$(tail -n1 "$RR/.git/plumbline/checks.tsv" | awk -F'\t' '{ print $4 "/" $8 }')" "AC-01-001=pass|SEC-01-005=xfail/SEC-01-005"
out=$(FAKE_XFAIL=SEC-01-005 aa --all "SEC-01-005" 2>&1); rc=$?
eq "reuse: the same --all is reused" "$rc/$(fakeruns)" "0/$((before + 1))"
assert "reuse: ...and says SEC-01-005: xfail, not pass" test -n "$(grep -x 'SEC-01-005: xfail' <<<"$out")"
sed -i 's/| deferred |/| verified |/' "$F1/security.md"
out=$(FAKE_XFAIL=SEC-01-005 aa --all "SEC-01-005" 2>&1); rc=$?
eq "reuse: once the finding is verified (a document change) the suite runs again, and the uncovered xfail fails" "$rc/$(fakeruns)" "1/$((before + 2))"
assert "reuse: ...with the expected-failure hint" has "$out" "only an own attack under a deferred or accepted finding may be an expected failure: SEC-01-005"
# A raw command proves no ID: its pass records ID=- and is never reused for that ID.
out=$(PLUMBLINE_TEST_AC="echo raw >> $FAKE_LOG" aa --all "AC-01-001" 2>&1)
eq "reuse: a raw command's pass is recorded with the ID unproven" "$(tail -n1 "$RR/.git/plumbline/checks.tsv" | awk -F'\t' '{ print $4 }')" "AC-01-001=-"
before=$(fakeruns)
out=$(PLUMBLINE_TEST_AC="echo raw >> $FAKE_LOG" aa --all "AC-01-001" 2>&1)
eq "reuse: ...so the same --all runs it again" "$(fakeruns)" "$((before + 1))"
unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
