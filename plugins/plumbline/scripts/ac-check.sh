#!/usr/bin/env bash
# The task gate's checks as a script, for work the TaskCompleted hook never sees
# (subagents, Quick changes): typecheck, lint and the tests named after the given
# AC or SEC IDs, through run_checks in lib.sh, so both pass or fail on the same commands.
#   ac-check.sh "AC-03-001|AC-03-002|SEC-03-001" [--surface <surface>] [--tests-only]
#   ac-check.sh --all ["<IDs>"] [--surface <surface>] [--tests-only] [--fresh]
# --surface names a row of docs/product/project.md and picks that surface's
# Typecheck, Lint and AC tests commands (the env vars still win); without it,
# the profile's only row is used, or the npm defaults when there is no profile.
# --tests-only skips typecheck and lint and runs just the tests (what a task needs; the
# full run belongs to the end of a workstream). It overrides a PLUMBLINE_TYPECHECK or
# PLUMBLINE_LINT you set, by emptying both for this run.
# A pass prints the adapter's per-ID lines (and the generic adapter's warning),
# then "ac-check: pass (<timing>)".
# --all is the whole-suite run (v0.6.2): typecheck, lint, then every test of the
# surface, not only the named ones (PLUMBLINE_AC_ALL=1 for the adapters); the IDs
# are optional and, when given, are reported pass, fail, xfail or missing from the
# same run. Without --surface, the surfaces are the feature's surfaces= in
# .plumbline, one after the other. After the per-ID lines it prints
#   ac-check: all tests on <surface>: <p> passed, <x> expected failures, <f> failed, <k> skipped (<n> without an ID) in <m>m <s>s
# (from the adapter's "ac-tests: counts" line; "counts unknown" for a raw or generic
# command, which runs with no IDs and is judged by its exit status), then the
# failing tests by name. A none AC tests cell runs typecheck and lint only.
# Only --all records and reuses a pass: a pass is kept in
# <git dir>/plumbline/checks.tsv under the code key (a hash of git ls-tree -r HEAD
# without Plumbline's own documents), the surface, a hash of the resolved commands and
# the IDs, and a later --all with the same key, surface, commands and a superset of
# the IDs prints "ac-check: reusing the full pass from <sha7> (<age>)" and each ID's
# recorded result (pass or xfail) instead of running. A pass whose expected failures
# are no longer all covered by a deferred or accepted finding isn't reused. A pass is
# recorded only when HEAD is the same before and after the run
# and nothing but those documents is uncommitted; a failure is never recorded.
# --fresh, or PLUMBLINE_REUSE=0 (which also stops recording), runs it anyway. The gates
# (security_run, the task gate) never pass --all, so they never reuse.
# Exit 0 = every check passed, 1 = a check failed (its per-ID lines and last 30 log lines go to
# stderr) or there is no AC test command for the surface, 2 = usage, or a
# surface the profile doesn't list, or no surface when it lists several.
source "$(dirname "${0//\\//}")/lib.sh"
usage() { echo 'usage: ac-check.sh "<AC or SEC IDs>" [--all] [--surface <surface>] [--tests-only] [--fresh]' >&2; exit 2; }

args="" surface="" tests_only=0 all=0 fresh=0
while (( $# )); do
  case "$1" in
    --surface)   (( $# >= 2 )) || usage; surface="$2"; shift 2 ;;
    --surface=*) surface="${1#*=}"; shift ;;
    --tests-only) tests_only=1; shift ;;
    --all)       all=1; shift ;;
    --fresh)     fresh=1; shift ;;
    -*)          usage ;;
    *)           args="$args $1"; shift ;;
  esac
done
# The same IDs the task gate would take from a task subject (AC- or SEC-).
ids=$(grep -oE '(AC|SEC)-[0-9]+-[0-9]+' <<<"$args" | sort -u | paste -sd'|' -)
[[ -n "$ids" ]] || (( all )) || usage
(( tests_only )) && export PLUMBLINE_TYPECHECK= PLUMBLINE_LINT=
# The adapters read PLUMBLINE_AC_ALL; only --all turns it on, whatever the caller's env says.
if (( all )); then export PLUMBLINE_AC_ALL=1; else unset PLUMBLINE_AC_ALL; fi

# A surface the profile can't resolve would run some other surface's commands.
surface_error() {
  profile_surface "$surface" >/dev/null
  if [[ $? == 2 ]]; then
    echo "ac-check: several surfaces in docs/product/project.md; pass --surface <one of: $(surface_list)>" >&2
  else
    echo "ac-check: unknown surface \"$surface\"; the profile lists: $(surface_list)" >&2
  fi
  exit 2
}

# --- Reuse of a full pass (--all only) ---
reuse_on=0
(( all )) && (( ! fresh )) && [[ "${PLUMBLINE_REUSE:-}" != 0 ]] && reuse_on=1
record_on=0
(( all )) && [[ "${PLUMBLINE_REUSE:-}" != 0 ]] && record_on=1

# True for a path that is one of Plumbline's own documents: a .md file under
# docs/product/ (contracts/ stays code: other work builds on it) or anything under a qa/ folder.
plumbline_doc() { # repo-relative path
  case "$1" in
    docs/product/*/contracts/*|docs/product/contracts/*) return 1 ;;
    docs/product/*.md|docs/product/*/qa/*|docs/product/qa/*) return 0 ;;
  esac
  return 1
}

hash_stdin() {
  if command -v sha1sum >/dev/null 2>&1; then sha1sum | cut -c1-40
  elif command -v shasum >/dev/null 2>&1; then shasum | cut -c1-40
  else cksum | cut -d' ' -f1; fi
}

# The tree at HEAD without Plumbline's own documents, as one hash. Fails with no commit.
code_key() {
  git -C "$PROJECT_DIR" rev-parse --verify -q HEAD >/dev/null 2>&1 || return 1
  # The same rule as plumbline_doc, in awk to stay quick on a big tree.
  git -C "$PROJECT_DIR" ls-tree -r HEAD 2>/dev/null | tr -d '\r' | awk -F'\t' '
    $2 ~ /^docs\/product\/(.*\/)?contracts\// { print; next }
    $2 ~ /^docs\/product\/.*\.md$/ || $2 ~ /^docs\/product\/(.*\/)?qa\// { next }
    { print }' | hash_stdin
}

# Uncommitted files other than Plumbline's own documents, one per line.
dirty_code() {
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] && ! plumbline_doc "$f" && printf '%s\n' "$f"
  done < <(dirty_files)
  return 0
}

state_dir() { local g; g=$(git -C "$PROJECT_DIR" rev-parse --absolute-git-dir 2>/dev/null) && printf '%s/plumbline\n' "$g"; }

# Hash of what the surface would run: the three commands, the generic commands
# section of the profile, and the AC-all switch. The env overrides are already in the commands.
commands_hash() { # typecheck lint tests
  { printf '%s\n%s\n%s\n' "$1" "$2" "$3"; section_body "$(project_file)" "Generic commands"; } | hash_stdin
}

fmt_age() { # seconds
  local s=$1
  if (( s < 90 )); then echo "${s}s ago"
  elif (( s < 5400 )); then echo "$(( (s + 30) / 60 )) min ago"
  elif (( s < 172800 )); then echo "$(( (s + 1800) / 3600 )) h ago"
  else echo "$(( s / 86400 )) days ago"; fi
}

# Prints the record's sha7, age and per-ID results (ID=pass|ID=xfail...) when a full
# pass can be reused: same key, surface and commands, its IDs include every requested
# one, and every expected failure the run saw is still covered by a deferred or
# accepted finding (security.md isn't part of the code key, so a finding marked
# verified since then means the suite runs again).
find_reuse() { # key surface cmdhash ids
  local f k s c r sha ep secs xf have ok id covered=""
  f="$(state_dir)/checks.tsv"; [[ -f "$f" ]] || return 1
  while IFS=$'\t' read -r k s c r sha ep secs xf _; do
    [[ "$k" == "$1" && "$s" == "${2:-default}" && "$c" == "$3" ]] || continue
    # Only IDs the run proved (pass or xfail) count; "-" is an ID no adapter reported.
    have="|$(tr '|' '\n' <<<"$r" | awk -F= '$2 == "pass" || $2 == "xfail" { print $1 }' | paste -sd'|' -)|"; ok=1
    for id in ${4//|/ }; do [[ "$have" == *"|$id|"* ]] || ok=0; done
    if (( ok )) && [[ -n "$xf" && "$xf" != - ]]; then
      [[ -n "$covered" ]] || covered="$(security_covered_ids)"$'\n.'
      for id in ${xf//|/ }; do grep -qxF -- "$id" <<<"$covered" || ok=0; done
    fi
    (( ok )) || continue
    printf '%s\t%s\t%s\n' "$sha" "$(fmt_age $(( $(date +%s) - ep )))" "$r"
    return 0
  done < <(tail -r "$f" 2>/dev/null || tac "$f" 2>/dev/null || cat "$f")
  return 1
}

# The per-ID results of the run just made, as ID=word joined by | (ID=- when no
# adapter line proved it, as with a raw or generic command), or - with no IDs.
run_results() { # sorted IDs
  [[ -n "$1" ]] || { echo -; return; }
  tr -d '\r' < "$RUN_CHECKS_LOG" | awk -v ids="$1" '
    BEGIN { n = split(ids, a, "|"); for (i = 1; i <= n; i++) want[a[i]] = 1 }
    /^(AC|SEC)-[0-9]+-[0-9]+: (pass|xfail)/ { i = index($0, ": "); id = substr($0, 1, i - 1); w = substr($0, i + 2); sub(/ .*/, "", w); if (id in want) got[id] = w }
    END { for (i = 1; i <= n; i++) printf "%s%s=%s", (i > 1 ? "|" : ""), a[i], (a[i] in got ? got[a[i]] : "-"); print "" }'
}

# Every expected failure of the run just made (the adapter's trailer), joined by |, or -.
run_xfails() {
  local x
  x=$(tr -d '\r' < "$RUN_CHECKS_LOG" | grep '^ac-tests: xfail only: ' | tail -n 1)
  x="${x#ac-tests: xfail only: }"
  x=$(tr -s ' ' '|' <<<"$x" | sed -e 's/^|//' -e 's/|$//')
  echo "${x:--}"
}

# One line per pass, eight tab-separated fields: code key, surface, commands hash,
# per-ID results, sha7, epoch, seconds, the run's expected failures.
record_pass() { # key surface cmdhash results sha seconds xfails
  local d f lock tmp i got=0 ids="${4:--}"
  d=$(state_dir) || return 0
  mkdir -p "$d" 2>/dev/null || return 0
  f="$d/checks.tsv"; lock="$d/checks.lock"
  # A lock left by a run that was killed mid-write would stop recording for good.
  [[ -d "$lock" && -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] && rmdir "$lock" 2>/dev/null
  for ((i = 0; i < 50; i++)); do
    mkdir "$lock" 2>/dev/null && { got=1; break; }
    sleep 0.1
  done
  (( got )) || return 0
  tmp=$(mktemp "$d/checks.XXXXXX") && {
    { [[ -f "$f" ]] && tail -n 19 "$f"; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "${2:-default}" "$3" "$ids" "$5" "$(date +%s)" "$6" "${7:--}"; } > "$tmp"
    mv -f "$tmp" "$f"
  }
  rmdir "$lock" 2>/dev/null
  return 0
}

# One surface: the usual checks, or the whole suite with --all. Returns 0 or 1; exits 2
# for a surface it can't use.
check_surface() { # surface
  surface="$1"
  local label="${surface:-default}" test_ac typecheck lint rc key cmdh head0 head1 t0 sorted reuse id
  # Unlike the task gate, a pass here has to mean the tests ran: an empty AC test
  # command (PLUMBLINE_TEST_AC="", or an AC tests cell of none) is refused, and so
  # is an empty AC tests cell. Typecheck and lint may still be skipped. With --all,
  # none means typecheck and lint only.
  test_ac=$(check_command PLUMBLINE_TEST_AC "$surface" "npm run -s test:ac --"); rc=$?
  case "$rc" in
    0) ;;
    3) echo "ac-check: $(ac_command_missing "$surface")" >&2; return 1 ;;
    *) surface_error ;;
  esac
  if [[ -z "$test_ac" ]] && (( ! all )); then
    echo "ac-check: no AC test command configured" >&2
    return 1
  fi

  sorted=$(tr '|' '\n' <<<"$ids" | grep . | sort -u | paste -sd'|' -)
  key="" head0=""
  if (( all && (reuse_on || record_on) )); then
    typecheck=$(check_command PLUMBLINE_TYPECHECK "$surface" "npm run -s typecheck") || typecheck=""
    lint=$(check_command PLUMBLINE_LINT "$surface" "npm run -s lint") || lint=""
    head0=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)
    if [[ -n "$head0" && -z "$(dirty_code)" ]] && key=$(code_key); then
      cmdh=$(commands_hash "$typecheck" "$lint" "$test_ac")
      if (( reuse_on )) && reuse=$(find_reuse "$key" "$surface" "$cmdh" "$sorted"); then
        local rsha rage rres w
        IFS=$'\t' read -r rsha rage rres <<<"$reuse"
        echo "ac-check: reusing the full pass from $rsha ($rage)"
        for id in ${sorted//|/ }; do
          w=$(tr '|' '\n' <<<"$rres" | awk -F= -v id="$id" '$1 == id { print $2; exit }')
          echo "$id: ${w:-pass}"
        done
        return 0
      fi
    else
      key=""
    fi
  fi

  t0=$SECONDS
  if run_checks "$ids" "$surface"; then
    local secs=$((SECONDS - t0))
    tr -d '\r' < "$RUN_CHECKS_LOG" | grep -E '^((AC|SEC)-[0-9]+-[0-9]+: |generic: |ac-tests: |ac-check: warning)'
    if (( ! all )); then :
    elif [[ -z "$test_ac" ]]; then echo "ac-check: all tests on $label: skipped (the AC tests command is none; typecheck and lint only)"
    else all_summary "$label" "$secs"; fi
    echo "ac-check: pass${RUN_CHECKS_TIMING:+ ($RUN_CHECKS_TIMING)}"
    if [[ -n "$key" ]]; then
      head1=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)
      [[ "$head1" == "$head0" && -z "$(dirty_code)" ]] && record_pass "$key" "$surface" "$cmdh" "$(run_results "$sorted")" "${head0:0:7}" "$secs" "$(run_xfails)"
    fi
    return 0
  fi
  [[ "$RUN_CHECKS_FAILED" == surface ]] && surface_error
  local what="$RUN_CHECKS_FAILED"
  if [[ "$what" == tests ]]; then
    if [[ -n "$ids" ]]; then what="tests for $ids"; else what="all tests"; fi
  fi
  echo "ac-check: $what failed" >&2
  [[ -n "$RUN_CHECKS_ERROR" ]] && echo "ac-check: $RUN_CHECKS_ERROR" >&2
  # The adapter prints its per-ID lines first; keep them when the tail cuts them off.
  if [[ "$RUN_CHECKS_FAILED" == tests ]] && (( $(wc -l < "$RUN_CHECKS_LOG") > 30 )); then
    tr -d '\r' < "$RUN_CHECKS_LOG" | grep -E '^((AC|SEC)-[0-9]+-[0-9]+: |generic: |ac-tests: )' >&2
  fi
  (( all )) && [[ "$RUN_CHECKS_FAILED" == tests ]] && all_summary "$label" "$((SECONDS - t0))" >&2
  tail -n 30 "$RUN_CHECKS_LOG" >&2
  return 1
}

# The all-tests line, from the adapter's "ac-tests: counts <passed> <xfail> <failed> <skipped> <noid>".
all_summary() { # surface label, seconds
  local counts secs="$2" tm
  counts=$(tr -d '\r' < "$RUN_CHECKS_LOG" | awk '$1 == "ac-tests:" && $2 == "counts" { p += $3; x += $4; f += $5; k += $6; n += $7; seen = 1 }
    END { if (seen) printf "%d passed, %d expected failure%s, %d failed, %d skipped (%d without an ID)", p, x, (x == 1 ? "" : "s"), f, k, n }')
  tm="${RUN_CHECKS_TIMING##*tests }"
  [[ "$RUN_CHECKS_TIMING" == *tests* ]] && secs="${tm%%s*}"
  printf 'ac-check: all tests on %s: %s in %dm %ds\n' "$1" "${counts:-counts unknown (generic)}" $((secs / 60)) $((secs % 60))
  tr -d '\r' < "$RUN_CHECKS_LOG" | grep '^ac-tests: failed: ' || true
}

trap 'rm -f "${RUN_CHECKS_LOG:-}"' EXIT
surfaces=("$surface")
if (( all )) && [[ -z "$surface" && -f "$(project_file)" ]]; then
  list=$(feature_meta surfaces | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep .)
  if [[ -n "$list" ]]; then
    surfaces=()
    while IFS= read -r s; do surfaces+=("$s"); done <<<"$list"
  fi
fi
# The IDs belong to one surface: with several, each would report the others' as missing.
if (( all )) && [[ -n "$ids" ]] && (( ${#surfaces[@]} > 1 )); then
  echo "ac-check: --all with IDs needs --surface <one of: $(IFS=,; echo "${surfaces[*]}" | sed 's/,/, /g')>: run it once per surface with that surface's IDs" >&2
  exit 2
fi
for s in "${surfaces[@]}"; do
  check_surface "$s" || exit 1
  rm -f "${RUN_CHECKS_LOG:-}"
done
exit 0
