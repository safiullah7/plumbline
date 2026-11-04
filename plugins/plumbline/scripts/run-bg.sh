#!/usr/bin/env bash
# run-bg.sh: start long runs and servers so they can be waited on and stopped later (v0.6.2).
#
# Why: Bash run_in_background (or a trailing &) only lets you kill the shell. Native
# children (node, Playwright, chromium) keep running and hold ports and memory.
# This script records exactly what it started, so it can stop exactly that: by recorded
# PID and start time, with the children of that process, never by name or pattern.
#
# Usage:
#   bash run-bg.sh start <name> -- <command...>   start detached; returns at once
#   bash run-bg.sh wait <name> [--max <seconds>]  wait for it to finish (default 540)
#   bash run-bg.sh status <name>                  running | finished (exit N) | gone
#   bash run-bg.sh list                           one line per run
#   bash run-bg.sh log <name> [--tail <n>]        last n log lines (default 40)
#   bash run-bg.sh stop <name>                    stop it and everything it started
#   bash run-bg.sh stop --all                     stop every run (for the main session only)
#
# <name> is [A-Za-z0-9._-]+. A single quoted argument after "--" runs as a shell command
# line (bash -c); several arguments run as a plain command.
# Give the Bash tool a 600000 ms timeout for "wait" (its default is 120000).
#
# Exit codes:
#   0  ok
#   1  start: that name is still running; stop: no such run
#   2  usage error (bad name, bad arguments, not in a git repo)
#   3  wait: still running when --max seconds passed; call wait again
#   4  wait: the wrapper died without writing an exit code
#   wait, when the run finished: the command's own exit code (so 3 and 4 can also
#   be the command's code; the "run-bg:" line says which)
#
# State: <git dir>/plumbline/procs/<name>.rec (key=value), .log, .snap.
# Record keys: name cmd pid winpid started started_epoch cwd log pgid setsid exit ended_epoch.
#
# How it works: start launches a waiting wrapper (this script, "_wrap"), with every file
# descriptor redirected, under nohup and disowned, so the calling Bash call returns at
# once and the run survives that call ending. The wrapper does not exec the command: from
# inside, it writes its own PID (and on Git Bash/MSYS/Cygwin its Windows PID from
# /proc/$$/winpid) and its start time, runs the command, then writes exit=<code>.
# Every ~30 s (PLUMBLINE_RUNBG_SNAPSHOT seconds) it saves its descendants to <name>.snap,
# so stop can still find survivors if the wrapper itself was killed.
# setsid is used only where it exists (not Git Bash, not macOS); the group is signalled
# only if the recorded pgid equals the wrapper PID.
#
# stop: checks the wrapper PID is alive AND its start time matches the record (Windows
# reuses PIDs fast); on a mismatch it leaves that process alone and drops the record.
# Windows: the live wrapper's descendants (Win32 + MSYS parent links, a child counts only if
# it was created after its parent) are killed one by one, children first, with
# taskkill //F //PID (never //T: its tree walk trusts stale parent links), then the wrapper.
# Whether the wrapper finished, died, or is stopped, processes from the last snapshot that are
# still alive with the same start time are stopped too and reported; start refuses a name
# while such leftovers are alive; status/list/wait show them.
# Elsewhere: TERM the group or the descendants (children first), wait 5 s, KILL survivors.
set -u

SELF="${BASH_SOURCE[0]//\\//}"           # backslashes -> slashes (C:\x\run-bg.sh)
case "$SELF" in /*|[A-Za-z]:/*) ;; *) SELF="$(pwd)/$SELF" ;; esac   # drive-letter paths are absolute

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$SELF"; }
die()   { echo "run-bg: $1" >&2; exit "${2:-2}"; }   # $1 = message, $2 = exit code

is_win=""
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) is_win=1 ;; esac

# --- process helpers ---
# Start time of an MSYS/Linux/macOS pid as the OS reports it ("" if gone).
proc_start() {
  local pid="$1" s
  if [[ -r /proc/$pid/stat ]]; then
    s=$(cat "/proc/$pid/stat" 2>/dev/null) || return 0
    s="${s##*) }"          # drop "pid (comm) "
    set -- $s              # state=1 ... starttime=20
    echo "${20:-}"
  else
    ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//;s/  */ /g'
  fi
}
pgid_of() {
  local s
  if [[ -r /proc/$1/stat ]]; then s=$(cat "/proc/$1/stat"); s="${s##*) }"; set -- $s; echo "${3:-}"
  else ps -o pgid= -p "$1" 2>/dev/null | tr -d ' '; fi
}
# All Windows processes: "pid ppid creation-ticks".
win_procs() {
  powershell.exe -NoProfile -Command 'Get-CimInstance Win32_Process | ForEach-Object { "$($_.ProcessId) $($_.ParentProcessId) $($_.CreationDate.Ticks)" }' 2>/dev/null | tr -d '\r'
}
# Descendants of pid $1 from "pid ppid [start]" lines on stdin: "pid start" lines, children first.
# A link child->parent is accepted only if the child was not created before its parent
# (when both creation times are known): a parent pid that was reused after the real parent
# died would otherwise adopt an unrelated, older orphan. Times compare as digit strings
# (ticks exceed double precision); lines with 2 fields (MSYS links) borrow times from 3-field lines.
# When the table has times (Windows), a link whose child or parent time is unknown is
# refused: a process created between the two listings has no time yet, and if it reused
# a dead parent's pid it would otherwise adopt that parent's old, unrelated children
# (seen live: a user's `pnpm run dev` tree from the night before). And no descendant may
# be older than the root itself. Without any times (Unix ps), links are taken as they are.
desc_filter() {
  awk -v r="$1" '
    function ge(a,b) { if (a=="" && b=="") return !timed
                       if (a=="" || b=="") return 0
                       if (length(a)!=length(b)) return length(a)>length(b)
                       return (a "")>=(b "") }
    {p[NR]=$1; pp[NR]=$2; n=NR; if (NF>=3 && $3!="") {tt[$1]=$3; timed=1}}
    END{inset[r]=1
        do{ch=0; for(i=1;i<=n;i++) if(!(p[i] in inset) && (pp[i] in inset) && ge(tt[p[i]], tt[pp[i]]) && (!timed || ge(tt[p[i]], tt[r]))){inset[p[i]]=1; order[++k]=p[i]; ch=1}} while(ch)
        for(i=k;i>=1;i--) print order[i], tt[order[i]]}'
}
# Descendants of an MSYS/Unix pid: "pid start" lines, children first.
unix_desc() {
  local l pid st
  ps -A -o pid= -o ppid= 2>/dev/null | desc_filter "$1" | while read -r pid st; do
    echo "$pid $(proc_start "$pid")"
  done
}
# Windows descendants of a Windows pid. The Win32 parent links alone are not enough:
# MSYS fork stubs exit and break the chain (taskkill //T then misses grandchildren), so
# the MSYS parent links (ps -W, as winpid pairs) are added to the Win32 ones.
win_desc() {
  { win_procs
    ps -W 2>/dev/null | awk 'NR>1{wp[$1]=$4; a[NR]=$1; b[NR]=$2; c[NR]=$4; n=NR}
      END{for(i=2;i<=n;i++) if(b[i]!=0 && (b[i] in wp)) print c[i], wp[b[i]]}'
  } | desc_filter "$1"
}
# Keep the "pid start" lines of a snapshot file that are still alive with the same start.
survivors() {
  local f="$1" pid st
  [[ -s "$f" ]] || return 0
  if [[ -n "$is_win" ]]; then
    # snapshot order is kept (children first); a live process matches on pid AND creation time
    awk 'NR==FNR{live[$1" "$3]=1;next} (($1" "$2) in live){print $1, $2}' <(win_procs) "$f"
  else
    while read -r pid st; do
      [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && [[ "$(proc_start "$pid")" == "$st" ]] && echo "$pid $st"
    done < "$f"
  fi
}

# Pids (space separated) from <name>'s last snapshot that are still alive with the recorded start time.
snap_alive() { survivors "$P/$1.snap" | awk '{printf "%s ", $1}'; }

fmt_elapsed() { local s=$1; [[ $s -lt 0 ]] && s=0; echo "$((s/60))m $((s%60))s"; }

# --- state ---
need_repo() {
  GD=$(git rev-parse --absolute-git-dir 2>/dev/null) || die "not in a git repo: run this from the project's repo"
  P="$GD/plumbline/procs"; mkdir -p "$P"
}
valid_name() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "bad name '$1': use letters, digits, . _ - only"; }
rec()  { echo "$P/$1.rec"; }
rget() { [[ -f "$1" ]] && grep -m1 "^$2=" "$1" | cut -d= -f2- | tr -d '\r'; }
# Write the record from the R_* variables (temp file + mv).
rec_write() {
  local f="$1" t; t=$(mktemp "$P/.rec.XXXXXX") || return 1
  {
    local k v
    for k in name cmd pid winpid started started_epoch cwd log pgid setsid exit ended_epoch; do
      eval "v=\${R_$k:-}"
      [[ -n "$v" ]] && printf '%s=%s\n' "$k" "$v"
    done
  } > "$t"
  mv -f "$t" "$f"
}
# Wrapper state of a record. Sets S (running | finished | gone), W_PID, W_EXIT.
state_of() {
  local f="$1" st
  W_EXIT=$(rget "$f" exit); W_PID=$(rget "$f" pid)
  if [[ -n "$W_EXIT" ]]; then S=finished; return; fi
  st=$(rget "$f" started)
  if [[ -n "$W_PID" ]] && kill -0 "$W_PID" 2>/dev/null && [[ "$(proc_start "$W_PID")" == "$st" ]]; then
    S=running
  else
    # the wrapper may have written its exit just now
    sleep 0.3; W_EXIT=$(rget "$f" exit)
    if [[ -n "$W_EXIT" ]]; then S=finished; else S=gone; fi
  fi
}
elapsed_of() { # record -> seconds
  local f="$1" a b; a=$(rget "$f" started_epoch); b=$(rget "$f" ended_epoch)
  [[ -z "$b" ]] && b=$(date +%s)
  echo $(( b - ${a:-$b} ))
}

# Rewrite snapshot file $1 (wrapper winpid $2, or "" on Unix): the current descendants, plus
# earlier entries that are still alive with the same start time. Keeping those matters: once
# the command exits, its own children are re-parented and can no longer be found from the
# wrapper, but they must stay in the snapshot so stop/start/status can still see them.
snap_update() {
  local snap="$1" new old
  if [[ -n "$2" ]]; then new=$(win_desc "$2" 2>/dev/null); else new=$(unix_desc $$ 2>/dev/null); fi
  old=$(survivors "$snap" 2>/dev/null)
  printf '%s\n%s\n' "$new" "$old" | awk 'NF>=2 && !seen[$0]++' > "$snap.tmp" 2>/dev/null
  mv -f "$snap.tmp" "$snap" 2>/dev/null
}

# --- the wrapper (internal) ---
wrap() {
  local name="$1"; shift; [[ "${1:-}" == "--" ]] && shift
  P="$RUNBG_DIR"; local f="$P/$name.rec" snap="$P/$name.snap" interval="${PLUMBLINE_RUNBG_SNAPSHOT:-30}"
  R_name="$name"; R_cmd="$RUNBG_CMD"; R_cwd="$PWD"; R_log="$P/$name.log"; R_started_epoch="$RUNBG_EPOCH"
  R_pid=$$
  [[ -r /proc/$$/winpid ]] && R_winpid=$(cat /proc/$$/winpid)
  R_started=$(proc_start $$)
  R_pgid=$(pgid_of $$)
  [[ -n "${RUNBG_SETSID:-}" ]] && R_setsid=1
  rec_write "$f"
  if [[ $# -eq 1 ]]; then bash -c "$1" & else "$@" & fi
  local cpid=$! tick=0
  while kill -0 "$cpid" 2>/dev/null; do
    sleep 1; tick=$((tick+1))
    if [[ $tick -eq 2 || $((tick % interval)) -eq 0 ]]; then
      snap_update "$snap" "${R_winpid:-}"
    fi
  done
  wait "$cpid"; local rc=$?
  [[ -f "$f" ]] || exit "$rc"          # stop already removed the record
  R_exit=$rc; R_ended_epoch=$(date +%s)
  rec_write "$f"
  exit "$rc"
}

# --- commands ---
cmd_start() {
  local name="${1:-}"; [[ -n "$name" ]] || die "start: name needed"; shift
  valid_name "$name"; need_repo
  [[ "${1:-}" == "--" ]] || die "start: use: start <name> -- <command...>"; shift
  [[ $# -gt 0 ]] || die "start: no command given"
  local f; f=$(rec "$name")
  if [[ -f "$f" ]]; then
    state_of "$f"
    if [[ "$S" == running ]]; then
      echo "run-bg: '$name' is still running (pid $W_PID); use another name, or stop it only if you started it: run-bg.sh stop $name" >&2; exit 1
    fi
    local left; left=$(snap_alive "$name")
    if [[ -n "$left" ]]; then
      echo "run-bg: '$name' ended but left processes running (pids ${left% }); run-bg.sh stop $name stops them (only if you started it), or use another name" >&2; exit 1
    fi
    rm -f "$f" "$P/$name.snap"
  fi
  local log="$P/$name.log" epoch; epoch=$(date +%s)
  : > "$log"
  local sid=""; command -v setsid >/dev/null 2>&1 && sid=1
  local oneline="$*"; oneline="${oneline//$'\n'/ }"
  export RUNBG_DIR="$P" RUNBG_CMD="$oneline" RUNBG_EPOCH="$epoch" RUNBG_SETSID="$sid"
  if [[ -n "$sid" ]]; then
    setsid nohup bash "$SELF" _wrap "$name" -- "$@" </dev/null >"$log" 2>&1 &
  else
    nohup bash "$SELF" _wrap "$name" -- "$@" </dev/null >"$log" 2>&1 &
  fi
  disown 2>/dev/null
  local i
  for i in $(seq 1 50); do
    [[ -n "$(rget "$f" started)" ]] && break
    sleep 0.2
  done
  [[ -n "$(rget "$f" started)" ]] || die "start: the wrapper did not come up; see $log" 1
  local pid winpid; pid=$(rget "$f" pid); winpid=$(rget "$f" winpid)
  # The log is read through this script (agents may not name .git/plumbline in a command).
  echo "run-bg: started $name (pid $pid${winpid:+, windows pid $winpid}); output: run-bg.sh log $name"
}

tail_log() { # name n
  local l="$P/$1.log"; [[ -f "$l" ]] && tail -n "$2" "$l"
}

cmd_wait() {
  local name="${1:-}" max=540; [[ -n "$name" ]] || die "wait: name needed"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in --max) max="${2:-}"; shift 2 ;; *) die "wait: unknown argument '$1'" ;; esac
  done
  [[ "$max" =~ ^[0-9]+$ ]] || die "wait: --max needs a number of seconds"
  valid_name "$name"; need_repo
  local f; f=$(rec "$name"); [[ -f "$f" ]] || die "no run named '$name'" 1
  local t0
  t0=$(date +%s)
  while :; do
    state_of "$f"
    if [[ "$S" == finished ]]; then
      echo "run-bg: $name finished (exit $W_EXIT) after $(fmt_elapsed "$(elapsed_of "$f")")"
      tail_log "$name" 20
      local lo; lo=$(snap_alive "$name")
      [[ -n "$lo" ]] && echo "run-bg: $name left processes running (pids ${lo% }); run-bg.sh stop $name stops them"
      exit "$W_EXIT"
    fi
    if [[ "$S" == gone ]]; then
      echo "run-bg: $name: the wrapper died without writing an exit code after $(fmt_elapsed "$(elapsed_of "$f")"); use stop $name to clean up"
      tail_log "$name" 20
      exit 4
    fi
    if [[ $(( $(date +%s) - t0 )) -ge $max ]]; then
      echo "run-bg: $name still running after $(fmt_elapsed "$(elapsed_of "$f")"); run wait again"
      exit 3
    fi
    sleep 2
  done
}

describe_state() { # record -> text
  state_of "$1"
  case "$S" in
    finished) echo "finished (exit $W_EXIT)$(leftover_note "$1")" ;;
    gone) echo "gone (wrapper died without exit)$(leftover_note "$1")" ;;
    *) echo running ;;
  esac
}
# ", leftover processes still running: pids" if the run's last snapshot has live members.
leftover_note() {
  local n="${1##*/}" l; n="${n%.rec}"; l=$(snap_alive "$n")
  [[ -n "$l" ]] && echo ", leftover processes still running: ${l% }"
  return 0
}

cmd_status() {
  local name="${1:-}"; [[ -n "$name" ]] || die "status: name needed"
  valid_name "$name"; need_repo
  local f; f=$(rec "$name"); [[ -f "$f" ]] || die "no run named '$name'" 1
  echo "$name: $(describe_state "$f"), elapsed $(fmt_elapsed "$(elapsed_of "$f")")"
  echo "command: $(rget "$f" cmd)"
  echo "--- last 5 log lines ---"
  tail_log "$name" 5
  return 0
}

cmd_list() {
  need_repo
  local f n any=""
  for f in "$P"/*.rec; do
    [[ -f "$f" ]] || continue
    any=1; n=$(rget "$f" name)
    local c; c=$(rget "$f" cmd); [[ ${#c} -gt 60 ]] && c="${c:0:57}..."
    printf '%s\t%s\t%s\t%s\n' "$n" "$(describe_state "$f")" "$(fmt_elapsed "$(elapsed_of "$f")")" "$c"
  done
  [[ -n "$any" ]] || echo "run-bg: no runs recorded"
  return 0
}

cmd_log() {
  local name="${1:-}" n=40; [[ -n "$name" ]] || die "log: name needed"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in --tail) n="${2:-}"; shift 2 ;; *) die "log: unknown argument '$1'" ;; esac
  done
  [[ "$n" =~ ^[0-9]+$ ]] || die "log: --tail needs a number"
  valid_name "$name"; need_repo
  [[ -f "$P/$name.log" ]] || die "no log for '$name'" 1
  tail_log "$name" "$n"
}

# Wait up to 5 s for every pid in $* to be gone.
all_gone() { local p; for p in "$@"; do kill -0 "$p" 2>/dev/null && return 1; done; return 0; }

stop_unix_pids() { # "pid" list (children first, wrapper last): TERM, 5 s, KILL
  local p i
  kill -TERM "$@" 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do all_gone "$@" && return 0; sleep 0.5; done
  for p in "$@"; do kill -0 "$p" 2>/dev/null && { kill -KILL "$p" 2>/dev/null; echo "run-bg:   killed (did not exit on TERM): $p"; }; done
  return 0
}

# Stop what <name>'s last snapshot lists and is still alive with the same start time
# (a reused pid never matches). Children first. Sets KILLED to the pids ("" if none).
# Windows: explicit taskkill //F //PID per process, never //T (its tree walk follows
# stale parent links and could reach unrelated processes).
KILLED=""
kill_snap() {
  local sv p _s; KILLED=""
  sv=$(survivors "$P/$1.snap"); [[ -n "$sv" ]] || return 0
  if [[ -n "$is_win" ]]; then
    while read -r p _s; do taskkill //F //PID "$p" >/dev/null 2>&1; done <<<"$sv"
  else
    stop_unix_pids $(echo "$sv" | awk '{print $1}')
  fi
  KILLED=$(echo "$sv" | awk '{printf "%s ", $1}'); KILLED="${KILLED% }"
}

stop_one() {
  local name="$1" f; f=$(rec "$name")
  [[ -f "$f" ]] || { echo "run-bg: no run named '$name'" >&2; return 1; }
  local pid winpid started pgid usesetsid
  pid=$(rget "$f" pid); winpid=$(rget "$f" winpid); started=$(rget "$f" started)
  pgid=$(rget "$f" pgid); usesetsid=$(rget "$f" setsid)
  local ex; ex=$(rget "$f" exit)
  if [[ -n "$ex" ]]; then
    # the wrapper finished, but it may have left processes behind (a server the script backgrounded)
    kill_snap "$name"
    rm -f "$f" "$P/$name.snap"
    echo "run-bg: $name already finished (exit $ex); ${KILLED:+stopped the processes it left running (pids $KILLED); }record removed"
    return 0
  fi
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    if [[ "$(proc_start "$pid")" != "$started" ]]; then
      echo "run-bg: $name: the recorded process is gone; pid $pid now belongs to another process; not stopping it"
      kill_snap "$name"
      [[ -n "$KILLED" ]] && echo "run-bg: $name: stopped the processes it had started (same pid and start time as in its snapshot): $KILLED"
      rm -f "$f" "$P/$name.snap"; return 0
    fi
    # live wrapper with matching start time
    if [[ -n "$winpid" ]]; then
      # children first (a few passes, in case they spawn more), then the wrapper
      # Each pid is killed on its own (no //T): win_desc already filtered out processes whose
      # parent link is stale, and taskkill's own tree walk has no such check.
      local d all="" pass p
      for pass in 1 2 3; do
        d=$(win_desc "$winpid" | awk '{print $1}')
        [[ -n "$d" ]] || break
        all="$all $(echo $d)"
        for p in $d; do taskkill //F //PID "$p" >/dev/null 2>&1; done
        sleep 0.5
      done
      echo "run-bg: stopping $name (windows pid $winpid; children:${all:- none})"
      taskkill //F //PID "$winpid" >/dev/null 2>&1
      local i; for i in 1 2 3 4 5 6; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    else
      local kids; kids=$(unix_desc "$pid" | awk '{printf "%s ", $1}')
      echo "run-bg: stopping $name (pid $pid; children: ${kids:-none})"
      if [[ -n "$usesetsid" && "$pgid" == "$pid" ]]; then kill -TERM -- "-$pgid" 2>/dev/null; fi
      stop_unix_pids $kids "$pid"
      if [[ -n "$usesetsid" && "$pgid" == "$pid" ]]; then kill -KILL -- "-$pgid" 2>/dev/null; fi
    fi
    rm -f "$f"
    rm -f "$f"
    kill_snap "$name"       # anything from the last snapshot that outlived the tree kill
    rm -f "$P/$name.snap"
    echo "run-bg: stopped $name${KILLED:+; also stopped leftovers from the last snapshot: $KILLED}"
    return 0
  fi
  # wrapper gone without an exit code
  echo "run-bg: $name: the wrapper (pid ${pid:-?}) is gone and wrote no exit code; looking for its survivors"
  kill_snap "$name"
  if [[ -z "$KILLED" ]]; then
    echo "run-bg: $name: no survivors from its last snapshot"
  else
    echo "run-bg: $name: stopped the survivors (same pid and start time as when the wrapper saw them): $KILLED"
  fi
  rm -f "$f" "$P/$name.snap"
  return 0
}

cmd_stop() {
  local a="${1:-}"; [[ -n "$a" ]] || die "stop: name or --all needed"
  need_repo
  if [[ "$a" == "--all" ]]; then
    local f n any="" rc=0
    for f in "$P"/*.rec; do
      [[ -f "$f" ]] || continue
      any=1; n=$(rget "$f" name); stop_one "$n" || rc=1
    done
    [[ -n "$any" ]] || echo "run-bg: nothing to stop"
    return $rc
  fi
  valid_name "$a"
  stop_one "$a" || exit 1
}

if [[ "${RUNBG_LIB:-}" == 1 ]]; then return 0 2>/dev/null || exit 0; fi   # sourced by the self-test: functions only

case "${1:-}" in
  _wrap) shift; wrap "$@" ;;
  start)  shift; cmd_start "$@" ;;
  wait)   shift; cmd_wait "$@" ;;
  status) shift; cmd_status "$@" ;;
  list)   shift; cmd_list ;;
  log)    shift; cmd_log "$@" ;;
  stop)   shift; cmd_stop "$@" ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
