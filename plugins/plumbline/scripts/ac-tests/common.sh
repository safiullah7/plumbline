#!/usr/bin/env bash
# The part every dedicated adapter (node, pytest, go) shares, sourced after the
# adapter has set NAME and usage(): argument parsing, AC/SEC ID normalisation, the
# run folder, the log files and the per-ID report. It sets dir, ids, re, run_dir,
# LOG and OUT, changes into run_dir, and defines report and finish. generic.sh
# has its own arguments and doesn't use it.

# --- Arguments and IDs ---
dir="" raw=""
while (( $# )); do
  case "$1" in
    --dir|--surface) (( $# >= 2 )) || usage; [[ "$1" == --dir ]] && dir="$2"; shift 2 ;;
    --dir=*)         dir="${1#*=}"; shift ;;
    --surface=*)     shift ;;
    -*)              usage ;;
    *)               raw="$raw $1"; shift ;;
  esac
done
# IDs split on |, commas or spaces; AC_01_001 and lowercase forms are accepted and
# reported as AC-01-001. SEC IDs (SEC-01-001) work the same. Anything else is a
# usage error.
ids=""
set -f   # no globbing of the split tokens
for tok in $(printf '%s\n' "$raw" | tr -d '\r' | tr '|,' '  '); do
  [[ "$tok" =~ ^([Aa][Cc]|[Ss][Ee][Cc])[-_]([0-9]+)[-_]([0-9]+)$ ]] || usage
  pre=$(printf %s "${BASH_REMATCH[1]}" | tr a-z A-Z)
  id="$pre-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
  case " $ids " in *" $id "*) ;; *) ids="${ids:+$ids }$id" ;; esac
done
set +f
# All-tests mode (PLUMBLINE_AC_ALL=1): the whole suite runs with no name filter, and
# the IDs may be empty (the adapters then skip -t, --grep, -k and -run).
ALL=0
[[ "${PLUMBLINE_AC_ALL:-}" == 1 ]] && ALL=1
[[ -n "$ids" || "$ALL" == 1 ]] || usage
# The runner's filter: AC-01-001 -> [Aa][Cc][-_]01[-_]001, SEC-01-001 ->
# [Ss][Ee][Cc][-_]01[-_]001, joined by |.
re=""
for id in $ids; do
  IFS=- read -r p a b <<<"$id"
  case "$p" in AC) p="[Aa][Cc]" ;; *) p="[Ss][Ee][Cc]" ;; esac
  re="${re:+$re|}$p[-_]$a[-_]$b"
done

# --dir is relative to the repo root (an absolute path is taken as is).
run_dir="$PROJECT_DIR"
if [[ -n "$dir" ]]; then
  case "$dir" in /*|[A-Za-z]:*) run_dir="$dir" ;; *) run_dir="$PROJECT_DIR/${dir#./}" ;; esac
fi
[[ -d "$run_dir" ]] || { echo "$NAME: no folder $run_dir" >&2; exit 1; }
cd "$run_dir" || exit 1

LOG=$(mktemp "${TMPDIR:-/tmp}/plumbline-ac.XXXXXX") || exit 1
OUT=$(mktemp "${TMPDIR:-/tmp}/plumbline-ac.XXXXXX") || exit 1
TRL=$(mktemp "${TMPDIR:-/tmp}/plumbline-ac.XXXXXX") || exit 1   # the xfail-only trailer
trap 'rm -f "$LOG" "$OUT" "$TRL"' EXIT

# The word every adapter uses for an expected failure that counts as one: the
# test failed as its marker said AND the marker's reason or the title names a
# finding ("finding #8", any case). Other markers (todo, xfail without a finding)
# are not xfail. Adapters that match in JS or awk use the same pattern.
#   finding[[:space:]]*#[0-9]+

# Reads "pass|fail|skip|xfail|xpass<TAB>test name" lines and prints one line per ID.
# xpass is a test marked as an expected failure naming a finding that passed: a
# fail, plus the line "ac-tests: passed but marked as an expected failure ...: <name>"
# so whoever closed the hole knows to remove the marker. An
# ID matches a name in any case with - or _ separators, and not when more digits
# follow (AC-01-001 isn't AC-01-0010). Per ID: any fail -> fail; else any xfail ->
# xfail; else any pass -> pass; else missing. Exit 0 only if every ID passed.
# With only xfail IDs as problems, it exits 1 and writes the trailer line
# "ac-tests: xfail only: <IDs>" to $TRL (finish prints it last).
# In all-tests mode it also prints "ac-tests: counts <passed> <xfail> <failed>
# <skipped> <noid>" over every line (noid = names with no AC/SEC ID, also counted
# in the other buckets), then "ac-tests: failed: <name>" for the first 50 fails,
# and the trailer lists every xfail test's IDs. A failed test makes it exit 1, and so
# does an xfail test with no AC or SEC ID (no finding can cover it), named on its own line.
report() {
  awk -F'\t' -v ids="$ids" -v all="$ALL" -v trl="$TRL" '
    BEGIN { n = split(ids, id, " "); for (i = 1; i <= n; i++) key[i] = tolower(id[i]) }
    {
      name = tolower($2); gsub(/_/, "-", name)
      if ($1 == "xpass") {
        if (++nxp <= 20) { t = $2; gsub(/^[ \t]+|[ \t]+$/, "", t); xpn[nxp] = t }
        $1 = "fail"
      }
      if (all) {
        hasid = match(name, /(ac|sec)-[0-9]+-[0-9]+/)
        if (!hasid) cn++
        # An expected failure no finding can cover (the test has no ID): a fail.
        if ($1 == "xfail" && !hasid) {
          if (++nnx <= 20) { t = $2; gsub(/^[ \t]+|[ \t]+$/, "", t); noid[nnx] = t }
          $1 = "fail"
        }
        if ($1 == "pass") cp++
        else if ($1 == "xfail") {
          cx++
          rest = name
          while (match(rest, /(ac|sec)-[0-9]+-[0-9]+/)) {
            xt[toupper(substr(rest, RSTART, RLENGTH))] = 1
            rest = substr(rest, RSTART + RLENGTH)
          }
        } else if ($1 == "fail") {
          cf++
          if (cf <= 50) { t = $2; gsub(/^[ \t]+|[ \t]+$/, "", t); failed[cf] = t }
        } else ck++
      }
      for (i = 1; i <= n; i++) {
        rest = name; hit = 0
        while ((p = index(rest, key[i])) > 0) {
          after = substr(rest, p + length(key[i]), 1)
          if (after !~ /[0-9]/) { hit = 1; break }
          rest = substr(rest, p + 1)
        }
        if (!hit) continue
        if ($1 == "pass") pass[i]++
        else if ($1 == "fail") fail[i]++
        else if ($1 == "xfail") xfail[i]++
      }
    }
    END {
      bad = 0
      for (i = 1; i <= n; i++) {
        if (fail[i]) { print id[i] ": fail"; bad = 1 }
        else if (xfail[i]) { print id[i] ": xfail"; xt[id[i]] = 1 }
        else if (pass[i]) print id[i] ": pass (" pass[i] ")"
        else { print id[i] ": missing"; bad = 1 }
      }
      for (i = 1; i <= nxp && i <= 20; i++)
        print "ac-tests: passed but marked as an expected failure (its hole looks closed: remove the marker and have the finding set to fixed): " xpn[i]
      for (i = 1; i <= nnx && i <= 20; i++)
        print "ac-tests: an expected failure without a SEC ID is a fail (only an own attack under a deferred or accepted finding may be one): " noid[i]
      if (all) {
        print "ac-tests: counts " cp + 0 " " cx + 0 " " cf + 0 " " ck + 0 " " cn + 0
        for (i = 1; i <= cf && i <= 50; i++) print "ac-tests: failed: " failed[i]
        if (cf) bad = 1
      }
      # In normal mode only requested IDs are in xt (set above).
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
}

# On any non-pass, the runner output tail helps the agent see why (not for an
# xfail-only run). The xfail-only trailer, when there is one, is the last line.
finish() { # report's exit code
  if [[ "$1" != 0 && ! -s "$TRL" ]]; then
    echo "--- $NAME output (last 40 lines) ---"
    tail -n 40 "$LOG"
  fi
  [[ -s "$TRL" ]] && cat "$TRL"
  exit "$1"
}

