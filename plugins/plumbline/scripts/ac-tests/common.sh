#!/usr/bin/env bash
# The part every dedicated adapter (node, pytest, go) shares, sourced after the
# adapter has set NAME and usage(): argument parsing, AC ID normalisation, the
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
# reported as AC-01-001. Anything else is a usage error.
ids=""
set -f   # no globbing of the split tokens
for tok in $(printf '%s\n' "$raw" | tr -d '\r' | tr '|,' '  '); do
  [[ "$tok" =~ ^[Aa][Cc][-_]([0-9]+)[-_]([0-9]+)$ ]] || usage
  id="AC-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
  case " $ids " in *" $id "*) ;; *) ids="${ids:+$ids }$id" ;; esac
done
set +f
[[ -n "$ids" ]] || usage
# The runner's filter: AC-01-001 -> [Aa][Cc][-_]01[-_]001, joined by |.
re=""
for id in $ids; do
  IFS=- read -r _ a b <<<"$id"
  re="${re:+$re|}[Aa][Cc][-_]$a[-_]$b"
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
trap 'rm -f "$LOG" "$OUT"' EXIT

# Reads "pass|fail|skip<TAB>test name" lines and prints one line per ID. An ID
# matches a name in any case with - or _ separators, and not when more digits
# follow (AC-01-001 isn't AC-01-0010). Exit 0 only if every ID passed.
report() {
  awk -F'\t' -v ids="$ids" '
    BEGIN { n = split(ids, id, " "); for (i = 1; i <= n; i++) key[i] = tolower(id[i]) }
    {
      name = tolower($2); gsub(/_/, "-", name)
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
      }
    }
    END {
      bad = 0
      for (i = 1; i <= n; i++) {
        if (fail[i]) { print id[i] ": fail"; bad = 1 }
        else if (pass[i]) print id[i] ": pass (" pass[i] ")"
        else { print id[i] ": missing"; bad = 1 }
      }
      exit bad
    }'
}

# On any non-pass, the runner output tail helps the agent see why.
finish() { # report's exit code
  if [[ "$1" != 0 ]]; then
    echo "--- $NAME output (last 40 lines) ---"
    tail -n 40 "$LOG"
  fi
  exit "$1"
}

