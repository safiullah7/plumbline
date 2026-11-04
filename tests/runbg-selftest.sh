#!/usr/bin/env bash
# Self-test for run-bg.sh (v0.6.2): detached start, wait/status/list/log, and stop
# killing grandchildren (MSYS and native node) by recorded PID. Run from the repo root:
#   bash tests/runbg-selftest.sh
# Works in a throwaway git repo. Every process it starts is stopped on exit.
set -u
RB="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts/run-bg.sh"
T=$(mktemp -d)
mkdir -p "$T/repo" "$T/tmp"
cd "$T/repo" && git init -q -b main && git config user.email t@t && git config user.name t
export TMPDIR="$T/tmp" PLUMBLINE_RUNBG_SNAPSHOT=1
windows=""; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) windows=1 ;; esac
have_node=""; command -v node >/dev/null 2>&1 && have_node=1
N=$((RANDOM+10000))                     # makes the marker commands unique to this run
NN=$((N+300000))                           # node timeout (ms) carrying the marker
ME="runbg-test-$$"

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
has()  { grep -qF -- "$2" <<<"$1"; }
rb()   { (cd "$T/repo" && bash "$RB" "$@"); }

# pids whose command line starts with "sleep <marker>" (MSYS/Unix)
find_sleep() {
  local d c
  if [[ -d /proc/self ]]; then
    for d in /proc/[0-9]*; do
      c=$(tr '\0' ' ' 2>/dev/null < "$d/cmdline") || continue
      case "$c" in "sleep $1"*) echo "${d#/proc/}" ;; esac
    done
  else
    ps -A -o pid= -o command= | awk -v m="sleep $1" 'index($0, m) { print $1 }'
  fi
}
# native node processes carrying the marker timeout (Windows: via Win32_Process; else ps)
find_node() {
  if [[ -n "$windows" ]]; then
    powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { \$_.CommandLine -like '*$1*' } | ForEach-Object { \$_.ProcessId }" 2>/dev/null | tr -d '\r'
  else
    ps -A -o pid= -o args= | awk -v m="setTimeout(()=>{},$1)" 'index($0, m) { print $1 }'
  fi
}
kill_leftovers() {
  local p
  for p in $(find_sleep "30[0-9].$N" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
  for p in $(find_node "$NN" 2>/dev/null); do
    if [[ -n "$windows" ]]; then taskkill //F //PID "$p" >/dev/null 2>&1; else kill -9 "$p" 2>/dev/null; fi
  done
}
cleanup() {
  rb stop --all >/dev/null 2>&1
  kill_leftovers
  cd / && rm -rf "$T"
}
trap cleanup EXIT

wait_for() { # seconds, command...: poll until it succeeds
  local n=$1 i; shift
  for ((i=0; i<n*5; i++)); do "$@" && return 0; sleep 0.2; done
  return 1
}

# --- start returns quickly; the run outlives the call and is visible from another call ---
t0=$(date +%s)
out=$(rb start a -- sleep 300.$N); rc=$?
t1=$(date +%s)
[[ $rc == 0 ]] && has "$out" "run-bg: started a (pid " && ok "start prints the started line" || fail "start (rc $rc): $out"
[[ $((t1-t0)) -lt 5 ]] && ok "start returns in under 5 s" || fail "start took $((t1-t0)) s"
out=$(bash -c "cd '$T/repo' && bash '$RB' status a"); has "$out" "a: running" && ok "a later bash call sees the run still running" || fail "status from another call: $out"

# --- die prints only the message, not its exit-code argument ---
out=$(rb log nosuch 2>&1); rc=$?
[[ $rc == 1 && "$out" == "run-bg: no log for 'nosuch'" ]] && ok "die: message only, exit 1" || fail "die output (rc $rc): '$out'"

# --- drive-letter and backslash script paths (Windows) ---
if [[ -n "$windows" ]] && command -v cygpath >/dev/null 2>&1; then
  for form in m w; do
    WRB=$(cygpath -$form "$RB")
    out=$(cd "$T/repo" && bash "$WRB" start "pth$form" -- sleep 300.$N 2>&1); rc=$?
    [[ $rc == 0 ]] && has "$out" "started pth$form" && ok "start via cygpath -$form path ($WRB)" || fail "start via -$form path (rc $rc): $out"
    (cd "$T/repo" && bash "$WRB" stop "pth$form" >/dev/null 2>&1)
  done
  wait_for 5 test -z "$(find_sleep "300.$N")" || true
fi

# --- desc_filter: a stale parent link (reused parent pid) must not adopt an older orphan ---
fl=$(RUNBG_LIB=1; source "$RB"; printf '%s\n' \
  "100 1 1000000000000000000" \
  "200 100 1000000000000000100" \
  "300 200 1000000000000000200" \
  "400 100 999999999999999000" \
  "500 400 1000000000000000300" \
  "600 1 1000000000000000150" \
  "700 1 999999999999999500" \
  "600 200" "700 100" | desc_filter 100 | awk '{print $1}' | tr '\n' ' ')
[[ "$fl" == "300 600 200 " || "$fl" == "600 300 200 " ]] && ok "desc_filter: children first, older orphan of a reused pid excluded ($fl)" || fail "desc_filter gave: '$fl'"
# The race seen live: 900 was created between the two listings (an MSYS link only, no
# time) and reused the pid of 800's long-dead parent; 800 (a user's dev server from the
# night before) must not be adopted through it, nor 801 below it.
fl=$(RUNBG_LIB=1; source "$RB"; printf '%s\n' \
  "100 1 1000000000000000000" \
  "200 100 1000000000000000100" \
  "800 900 900000000000000000" \
  "801 800 900000000000000050" \
  "900 200" | desc_filter 100 | awk '{print $1}' | tr '\n' ' ')
[[ "$fl" == "200 " ]] && ok "desc_filter: a parent with no time adopts nothing, so an old tree behind a reused pid is left alone ($fl)" || fail "desc_filter race: '$fl'"
fl=$(RUNBG_LIB=1; source "$RB"; printf '%s\n' "100 1 1000000000000000000" "200 100 1000000000000000100" "300 200" | desc_filter 100 | awk '{print $1}' | tr '\n' ' ')
[[ "$fl" == "200 " ]] && ok "desc_filter: ...and a child with no time isn't taken in a timed table ($fl)" || fail "desc_filter untimed child: '$fl'"
fl=$(RUNBG_LIB=1; source "$RB"; printf '%s\n' "10 1" "11 10" "12 11" | desc_filter 10 | awk '{print $1}' | tr '\n' ' ')
[[ "$fl" == "12 11 " ]] && ok "desc_filter: plain pid/ppid table (no times) still works" || fail "desc_filter plain: '$fl'"

# --- a run that finishes but leaves a process behind: shown, blocks the name, stop kills it ---
rb start v -- bash -c "sleep 309.$N & sleep 4" >/dev/null
rb wait v --max 30 >/dev/null
out=$(rb status v); has "$out" "finished (exit 0), leftover processes still running" && ok "status: finished with leftovers" || fail "status leftovers: $out"
out=$(rb list); has "$out" "leftover processes still running" && ok "list: finished with leftovers" || fail "list leftovers: $out"
out=$(rb start v -- true 2>&1); rc=$?
[[ $rc == 1 ]] && has "$out" "left processes running" && has "$out" "stop v" && ok "start refuses a name with leftovers (exit 1)" || fail "start with leftovers (rc $rc): $out"
out=$(rb stop v); rc=$?
[[ $rc == 0 ]] && has "$out" "already finished (exit 0)" && has "$out" "stopped the processes it left running" && ok "stop on a finished run kills and reports the leftovers" || fail "stop leftovers (rc $rc): $out"
wait_for 10 test -z "$(find_sleep "309.$N")" && ok "the leftover process is gone" || fail "leftover sleep 309 still alive"
[[ -n "$(find_sleep "300.$N")" ]] && ok "the command process is alive" || fail "command process not found"

# --- refuse a running name ---
out=$(rb start a -- sleep 1 2>&1); rc=$?
[[ $rc == 1 ]] && has "$out" "still running" && ok "start refuses a running name (exit 1)" || fail "refuse running (rc $rc): $out"
has "$out" "use another name" && has "$out" "only if you started it" && ok "refusal hint: another name, or stop only your own" || fail "refusal hint: $out"

# --- wait: timeout path ---
out=$(rb wait a --max 2); rc=$?
[[ $rc == 3 ]] && has "$out" "still running after" && ok "wait --max: exit 3, says still running" || fail "wait timeout (rc $rc): $out"

# --- stop a plain run ---
out=$(rb stop a); rc=$?
[[ $rc == 0 ]] && has "$out" "stopped a" && ok "stop a: reports stopped" || fail "stop a (rc $rc): $out"
wait_for 5 test -z "$(find_sleep "300.$N")" && ok "stop a: the process is gone" || fail "stop a: process still alive"
out=$(rb status a 2>&1); rc=$?
[[ $rc == 1 ]] && ok "stop a: record removed" || fail "record still there (rc $rc): $out"

# --- finish path: exit code passed through, log, status, list ---
rb start b -- bash -c 'echo line1; echo line2; echo line3; exit 7' >/dev/null
out=$(rb wait b --max 30); rc=$?
[[ $rc == 7 ]] && ok "wait passes the command's exit code (7)" || fail "wait exit (rc $rc): $out"
has "$out" "finished (exit 7)" && has "$out" "line3" && ok "wait prints finished line and the log tail" || fail "wait output: $out"
out=$(rb status b); has "$out" "b: finished (exit 7)" && has "$out" "line1" && ok "status: finished (exit 7) with log lines" || fail "status: $out"
out=$(rb list); has "$out" "b" && has "$out" "finished (exit 7)" && ok "list shows the finished run" || fail "list: $out"
out=$(rb log b --tail 1); [[ "$out" == "line3" ]] && ok "log --tail 1 gives the last line" || fail "log --tail 1: $out"
out=$(rb log b); has "$out" "line1" && ok "log default shows the output" || fail "log: $out"

# --- replace a finished record; bad names; outside a repo ---
out=$(rb start b -- bash -c 'exit 0'); rc=$?
[[ $rc == 0 ]] && ok "start replaces a finished record" || fail "replace finished (rc $rc): $out"
rb wait b --max 30 >/dev/null
out=$(rb status b); has "$out" "finished (exit 0)" && ok "the replaced run is the new one" || fail "after replace: $out"
rb start 'bad name' -- true >/dev/null 2>&1; rc=$?
[[ $rc == 2 ]] && ok "bad name (space): exit 2" || fail "bad name (rc $rc)"
rb start 'a/b' -- true >/dev/null 2>&1; rc=$?
[[ $rc == 2 ]] && ok "bad name (slash): exit 2" || fail "bad name slash (rc $rc)"
mkdir -p "$T/norepo"; (cd "$T/norepo" && GIT_CEILING_DIRECTORIES="$T" bash "$RB" list >/dev/null 2>&1); rc=$?
[[ $rc == 2 ]] && ok "outside a git repo: exit 2" || fail "outside repo (rc $rc)"
out=$(rb stop b); has "$out" "already finished (exit 0)" && ok "stop on a finished run just removes it" || fail "stop finished: $out"

# --- stop kills an MSYS grandchild and a native node grandchild ---
if [[ -n "$have_node" ]]; then
  rb start g -- bash -c "node -e 'setTimeout(()=>{},$NN)' & bash -c 'sleep 301.$N & sleep 302.$N'" >/dev/null
else
  rb start g -- bash -c "bash -c 'sleep 301.$N & sleep 302.$N'" >/dev/null
fi
wait_for 10 test -n "$(find_sleep "302.$N")" && ok "grandchildren are running (sleep 301/302)" || fail "grandchildren did not start"
if [[ -n "$have_node" ]]; then
  wait_for 10 test -n "$(find_node "$NN")" && ok "native node grandchild is running" || fail "node grandchild did not start"
fi
out=$(rb stop g); rc=$?
[[ $rc == 0 ]] && has "$out" "stopped g" && ok "stop g reports stopped" || fail "stop g (rc $rc): $out"
wait_for 10 test -z "$(find_sleep "30[12].$N")" && ok "stop killed the MSYS grandchildren" || fail "sleep grandchildren still alive"
if [[ -n "$have_node" ]]; then
  wait_for 10 test -z "$(find_node "$NN")" && ok "stop killed the native node grandchild" || fail "node grandchild still alive: $(find_node "$NN" | tr '\n' ' ')"
fi

# --- a stale record: the recorded pid now belongs to another process ---
rb start s -- sleep 303.$N >/dev/null
R=$(cd "$T/repo" && git rev-parse --absolute-git-dir)/plumbline/procs/s.rec
wait_for 20 test -s "$(dirname "$R")/s.snap"     # the snapshot is written after ~2 s
cp "$R" "$T/s.rec.orig"
sed 's/^started=.*/started=1/' "$T/s.rec.orig" > "$R"
out=$(rb stop s); rc=$?
[[ $rc == 0 ]] && has "$out" "now belongs to another process; not stopping it" && ok "stale record: reported, nothing stopped" || fail "stale (rc $rc): $out"
has "$out" "stopped the processes it had started" && ok "stale record: the wrapper's own snapshot children are stopped, the reused pid is not" || fail "stale record: no snapshot kill reported: $out"
[[ ! -f "$R" ]] && ok "stale record: record removed" || fail "stale record still there"
cp "$T/s.rec.orig" "$R"; rb stop s >/dev/null     # now really stop it
wait_for 5 test -z "$(find_sleep "303.$N")" && ok "stale test cleaned up" || fail "stale test: process left"

# --- the wrapper is gone: stop reports it and stops the survivors from the snapshot ---
rb start w -- bash -c "sleep 304.$N & sleep 305.$N" >/dev/null
R=$(cd "$T/repo" && git rev-parse --absolute-git-dir)/plumbline/procs
sleep 6   # the snapshot is taken after 2 s and then every PLUMBLINE_RUNBG_SNAPSHOT s
wpid=$(grep '^pid=' "$R/w.rec" | cut -d= -f2); wwin=$(grep '^winpid=' "$R/w.rec" | cut -d= -f2)
[[ -s "$R/w.snap" ]] && ok "the wrapper wrote a descendants snapshot" || fail "no snapshot"
if [[ -n "$wwin" ]]; then taskkill //F //PID "$wwin" >/dev/null 2>&1; else kill -9 "$wpid" 2>/dev/null; fi
sleep 1
out=$(rb start w -- true 2>&1); rc=$?
[[ $rc == 1 ]] && has "$out" "left processes running" && ok "start refuses to reuse a gone name while its survivors live" || fail "start over gone record (rc $rc): $out"
[[ -f "$R/w.rec" ]] && ok "the gone record was not deleted" || fail "gone record deleted"
out=$(rb stop w); rc=$?
[[ $rc == 0 ]] && has "$out" "is gone and wrote no exit code" && ok "wrapper gone: stop says so" || fail "wrapper gone (rc $rc): $out"
has "$out" "survivors" && ok "wrapper gone: survivors listed" || fail "no survivors listed: $out"
wait_for 10 test -z "$(find_sleep "30[45].$N")" && ok "wrapper gone: survivors stopped by pid" || fail "survivors still alive"

# --- status/wait on a wrapper that died without an exit code ---
rb start d -- sleep 306.$N >/dev/null
dpid=$(grep '^pid=' "$R/d.rec" | cut -d= -f2); dwin=$(grep '^winpid=' "$R/d.rec" | cut -d= -f2)
if [[ -n "$dwin" ]]; then taskkill //F //PID "$dwin" >/dev/null 2>&1; else kill -9 "$dpid" 2>/dev/null; fi
sleep 1
out=$(rb wait d --max 10); rc=$?
[[ $rc == 4 ]] && has "$out" "died without writing an exit code" && ok "wait on a dead wrapper: exit 4" || fail "wait dead (rc $rc): $out"
out=$(rb status d); has "$out" "gone" && ok "status: gone" || fail "status gone: $out"
rb stop d >/dev/null
for p in $(find_sleep "306.$N"); do kill -9 "$p" 2>/dev/null; done

# --- stop --all ---
rb start x1 -- sleep 307.$N >/dev/null
rb start x2 -- bash -c "sleep 308.$N & wait" >/dev/null
rb start x3 -- bash -c 'exit 0' >/dev/null
wait_for 10 test -n "$(find_sleep "308.$N")" || true
out=$(rb stop --all); rc=$?
[[ $rc == 0 ]] && has "$out" "stopped x1" && has "$out" "stopped x2" && ok "stop --all stops every run" || fail "stop --all (rc $rc): $out"
wait_for 10 test -z "$(find_sleep "30[78].$N")" && ok "stop --all: processes gone" || fail "stop --all: processes left"
out=$(rb list); has "$out" "no runs recorded" && ok "stop --all: no records left" || fail "list after --all: $out"

echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
