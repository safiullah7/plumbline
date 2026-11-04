#!/usr/bin/env bash
# Runs several AC test adapters over the same IDs and merges their reports, so
# one criterion can be proven by a unit test and an e2e test in different runners.
#   combine.sh --cmd "<command>" [--cmd "<command>" ...] "AC-01-001|AC-01-002"
# Each command is a full adapter invocation without the IDs, for example
#   --cmd 'bash "$S/ac-tests/node.sh" --dir web' --cmd 'bash "$S/ac-tests/playwright.sh" --dir web'
# check_command in lib.sh writes this from an AC tests cell of `node --dir web +
# playwright --dir web`. combine.sh appends the IDs as one quoted last argument
# and runs the command in the repo root (eval, so quoting works as in a shell).
# It reads the "AC-01-001: pass (2)" / "fail" / "missing" lines each prints and
# prints one line per ID: "fail" if any command reports fail; else "xfail" if any
# reports xfail; else "pass (n)", n summed over the commands that pass it; else
# "missing". In all-tests mode (PLUMBLINE_AC_ALL=1; IDs optional) it also sums the
# commands' "ac-tests: counts" lines, passes on their "ac-tests: failed:" lines
# and merges their "ac-tests: xfail only:" trailers into one, printed last. A command's exit code
# only matters when it fails with no per-ID line at all (the runner isn't
# installed, the command doesn't exist): its output is then shown and the whole
# run fails. A command that exits 0 without per-ID lines (a raw command, the
# generic adapter) proves nothing, so a note says so. generic's warning is passed on.
# Exit 0 = every ID passes; 1 = otherwise (the failing commands' output follows,
# last 40 lines each, minus the per-ID lines); 2 = usage.
source "$(dirname "${0//\\//}")/../lib.sh"
usage() { echo "usage: combine.sh --cmd \"<command>\" [--cmd \"<command>\" ...] \"<AC IDs>\"" >&2; exit 2; }

cmds=() raw=""
while (( $# )); do
  case "$1" in
    --cmd)   (( $# >= 2 )) && [[ -n "${2//[[:space:]]/}" ]] || usage; cmds+=("$2"); shift 2 ;;
    --cmd=*) [[ -n "${1#*=}" ]] || usage; cmds+=("${1#*=}"); shift ;;
    -*)      usage ;;
    *)       raw="$raw $1"; shift ;;
  esac
done
(( ${#cmds[@]} )) || usage
# IDs split on |, commas or spaces, as in common.sh; each adapter gets the string as given.
ids=""
set -f
for tok in $(printf '%s\n' "$raw" | tr -d '\r' | tr '|,' '  '); do
  [[ "$tok" =~ ^([Aa][Cc]|[Ss][Ee][Cc])[-_]([0-9]+)[-_]([0-9]+)$ ]] || usage
  pre=$(printf %s "${BASH_REMATCH[1]}" | tr a-z A-Z)
  id="$pre-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
  case " $ids " in *" $id "*) ;; *) ids="${ids:+$ids }$id" ;; esac
done
set +f
ALL=0
[[ "${PLUMBLINE_AC_ALL:-}" == 1 ]] && ALL=1   # all-tests mode: no IDs needed
[[ -n "$ids" || "$ALL" == 1 ]] || usage
given="${raw# }"

W=$(mktemp -d "${TMPDIR:-/tmp}/plumbline-combine.XXXXXX") || exit 1
trap 'rm -rf "$W"' EXIT

# --- Run every command (all of them, so one report shows every problem) ---
# A part's lines: per-ID lines, "ac-tests: counts ..." and "ac-tests: failed: ..."
# (all-tests mode), and the "ac-tests: xfail only: ..." trailer.
lines_re='^((AC|SEC)-[0-9]+-[0-9]+: (pass|fail|xfail|missing)|ac-tests: (counts|failed:|xfail only:))'
bad=0 warned=""
for i in "${!cmds[@]}"; do
  # In all-tests mode a raw part (not an adapter) gets no IDs, as in run_checks: the
  # IDs would be a filter, not the whole suite. No part gets an empty argument.
  if [[ "$ALL" == 1 && ( "${cmds[$i]}" != */ac-tests/* || -z "$given" ) ]]; then
    [[ "${cmds[$i]}" != */ac-tests/* ]] && echo "ac-check: warning: a raw part runs with no IDs in all-tests mode, judged by its exit status: ${cmds[$i]}"
    (cd "$PROJECT_DIR" && eval "${cmds[$i]}") 2>&1 | tr -d '\r' > "$W/out.$i"
  else
    (cd "$PROJECT_DIR" && eval "${cmds[$i]} \"\$given\"") 2>&1 | tr -d '\r' > "$W/out.$i"
  fi
  rc=${PIPESTATUS[0]}
  grep -E "$lines_re" "$W/out.$i" > "$W/ac.$i"
  if [[ "$rc" != 0 ]]; then
    echo "$i" >> "$W/failed"
    [[ -s "$W/ac.$i" ]] || bad=1            # a runner problem
  elif [[ ! -s "$W/ac.$i" && "$ALL" != 1 ]]; then
    echo "combine: no per-ID lines from: ${cmds[$i]} (exit 0), so it proves none of the IDs"
  fi
  w=$(grep -m1 '^generic: ' "$W/out.$i")
  if [[ -n "$w" && "$warned" != *"[$w]"* ]]; then warned="$warned[$w]"; echo "$w"; fi
done

# --- Merge ---
# Per ID: any fail -> fail; else any xfail -> xfail; else pass (counts summed); else
# missing. The counts add up. The trailer lists the requested xfail IDs and every ID
# a part's own trailer named (an unrequested xfail test in all-tests mode); it is
# written to a file, to be printed last.
: > "$W/trailer"
cat "$W"/ac.* | awk -v ids="$ids" -v trl="$W/trailer" '
  BEGIN { n = split(ids, id, " ") }
  /^ac-tests: counts / { for (j = 1; j <= 5; j++) cnt[j] += $(2 + j); seen = 1; next }
  /^ac-tests: failed: / { if (++nf <= 50) failed[nf] = $0; next }
  /^ac-tests: xfail only: / { for (j = 4; j <= NF; j++) xt[$j] = 1; next }
  {
    key = $1; sub(/:$/, "", key); st = $2
    if (st == "fail") fail[key] = 1
    else if (st == "xfail") xfail[key] = 1
    else if (st == "pass") { c = 1; if (match($0, /\([0-9]+\)/)) c = substr($0, RSTART + 1, RLENGTH - 2) + 0; pass[key] += c }
  }
  END {
    bad = 0
    for (i = 1; i <= n; i++) {
      k = id[i]
      if (fail[k]) { print k ": fail"; bad = 1 }
      else if (xfail[k]) { print k ": xfail"; xt[k] = 1 }
      else if (pass[k]) print k ": pass (" pass[k] ")"
      else { print k ": missing"; bad = 1 }
    }
    if (seen) {
      print "ac-tests: counts " cnt[1] + 0 " " cnt[2] + 0 " " cnt[3] + 0 " " cnt[4] + 0 " " cnt[5] + 0
      for (i = 1; i <= nf; i++) print failed[i]
      if (cnt[3] > 0) bad = 1
    }
    nx = 0
    for (k in xt) { nx++; list[nx] = k }
    for (i = 2; i <= nx; i++) {
      v = list[i]
      for (j = i - 1; j >= 1 && list[j] > v; j--) list[j + 1] = list[j]
      list[j + 1] = v
    }
    if (nx && !bad) {
      line = "ac-tests: xfail only:"
      for (i = 1; i <= nx; i++) line = line " " list[i]
      print line > trl
    }
    exit (bad || nx > 0)
  }'
merged=$?

[[ "$merged" == 0 && "$bad" == 0 ]] && exit 0
# A command that exits 1 for an ID another command passes doesn't fail the run,
# so the tails are printed only now, for every command that exited non-zero. An
# xfail-only run (the trailer) has no tails: nothing failed.
if [[ -s "$W/failed" && ( "$bad" != 0 || ! -s "$W/trailer" ) ]]; then
  while IFS= read -r i; do
    echo "--- ${cmds[$i]} (last 40 lines) ---"
    grep -vE "$lines_re" "$W/out.$i" | tail -n 40
  done < "$W/failed"
fi
[[ "$bad" == 0 ]] && cat "$W/trailer"
exit 1
