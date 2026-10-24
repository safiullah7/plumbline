#!/usr/bin/env bash
# AC test adapter for pytest: runs the tests named after the given AC IDs and
# reports each ID.
#   pytest.sh [--dir <path>] [--surface <s>] "AC-01-001|AC-01-002"
# Runs `python -m pytest -k "ac_01_001 or ac_01_002" -rA -q` in the run folder,
# with the first Python that can import pytest: .venv or venv in the run folder,
# then .venv in the repo root, then python, then python3.
# Prints one line per ID: "AC-01-001: pass (2)", "AC-01-001: fail" or
# "AC-01-001: missing", then the runner's output tail when any ID isn't a pass.
# Exit 0 = every ID has a passing test and none failing; 1 = otherwise, or pytest
# isn't installed; 2 = usage.
#
# Rules: the ID is matched in the whole node ID (file, class, test and
# parameters), as -k matches it. PASSED counts as a pass, FAILED and ERROR as
# fails. SKIPPED, XFAIL and XPASS count as neither, so an ID whose only tests are
# skipped or xfail is "missing". A strict xfail that passes is reported FAILED.
#
# Verified (Python 3.12.10, pytest 9.0.3, Oct 2026):
# - -k is case-insensitive and matches substrings of names, so "ac_01_001"
#   selects test_AC_01_001_x and TestAC_01_001::test_y. Dashes aren't valid in a
#   -k expression, hence the underscore form; a test with the ID only in a
#   parametrize id written with dashes isn't selected.
# - -rA prints the short summary as "PASSED <nodeid>", "FAILED <nodeid> - msg",
#   "ERROR <nodeid> - msg", "XFAIL <nodeid>", "XPASS <nodeid>" and
#   "SKIPPED [n] <file>:<line>: reason" (no test name, so skips can't be matched).
# - A collection error prints "ERROR <file>" and runs nothing; exit 5 = no tests.
# - -p no:cacheprovider keeps .pytest_cache out of the repo.
source "$(dirname "${0//\\//}")/../lib.sh"
NAME=pytest
usage() { echo "usage: $NAME.sh [--dir <path>] [--surface <s>] \"<AC IDs>\"" >&2; exit 2; }

# --- Arguments and IDs (the same block in every adapter) ---
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

# --- Runner ---
py=""
for c in "$run_dir/.venv/bin/python" "$run_dir/.venv/Scripts/python.exe" \
         "$run_dir/venv/bin/python" "$run_dir/venv/Scripts/python.exe" \
         "$PROJECT_DIR/.venv/bin/python" "$PROJECT_DIR/.venv/Scripts/python.exe" \
         python python3; do
  # The Windows Store alias "python3" exists but only prints a hint, so each
  # candidate has to import pytest to be chosen.
  if "$c" -c 'import pytest' >/dev/null 2>&1; then py="$c"; break; fi
done
[[ -n "$py" ]] || { echo "$NAME: not installed"; exit 1; }

kexpr=""
for id in $ids; do
  IFS=- read -r _ a b <<<"$id"
  kexpr="${kexpr:+$kexpr or }ac_${a}_$b"
done

COLUMNS=200 NO_COLOR=1 "$py" -m pytest -k "$kexpr" -rA -q -p no:cacheprovider 2>&1 \
  | tr -d '\r' > "$LOG"
# Summary lines to "status<TAB>node id".
awk '
  /^PASSED /         { print "pass\t" $2; next }
  /^(FAILED|ERROR) / { print "fail\t" $2; next }
' "$LOG" | report
finish $?
