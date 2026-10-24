#!/usr/bin/env bash
# Shared helpers for the Plumbline hooks and scripts. Runs in bash on macOS and
# Linux, and in Git Bash on Windows.

# Forward slashes, and /c/... instead of C:\... on Windows, so paths compare.
# Going through the Windows form first gives every folder a single spelling, even
# one Git Bash mounts under two names (/tmp and /c/Users/<you>/AppData/Local/Temp).
norm_path() {
  local p="${1//\\//}" w
  if command -v cygpath >/dev/null 2>&1; then
    w=$(cygpath -m "$p" 2>/dev/null) || w="$p"
    p=$(cygpath -u "$w" 2>/dev/null || printf '%s' "$p")
  fi
  printf '%s\n' "${p%/}"
}

# Hooks always have CLAUDE_PROJECT_DIR. A script run from a Bash that has cd'd into
# a subfolder (apps/api) falls back to the git root, then to the current folder.
PROJECT_DIR=$(norm_path "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")

# This plugin's scripts folder, so agents can be told where to run them from.
PLUMBLINE_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]//\\//}")" && pwd)"

# jq, minus the \r that Windows builds of jq add to every line.
jqr() { jq -r "$@" | tr -d '\r'; }

# A gate that can't read its input must say so, not silently allow everything.
require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "Plumbline: jq isn't installed or isn't on PATH, so this gate can't run." >&2
  echo "Install jq (Windows: winget install jqlang.jq), restart Claude Code, and retry." >&2
  exit 2
}

# Absolute path of the active phase folder, from .claude/current-phase.
phase_dir() {
  local f="$PROJECT_DIR/.claude/current-phase"
  [[ -f "$f" ]] && echo "$PROJECT_DIR/$(head -n1 "$f" | tr -d '\r')"
}

# Phase folder relative to the repo root, for messages.
phase_rel() {
  local dir
  dir=$(phase_dir) || return 1
  printf '%s\n' "${dir#"$PROJECT_DIR"/}"
}

# The dev plan's Status value (DRAFT, READY, ...), empty when there's no plan.
plan_status() {
  local dir
  dir=$(phase_dir) || return 1
  grep -m1 -iE '^Status:' "$dir/dev-plan.md" 2>/dev/null | tr -d '\r' \
    | sed -E 's/^[Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]*//'
}

# True once the lead has marked the dev plan "Status: READY".
# Gates are enforced only from then on, so discovery and planning run freely.
build_active() {
  local dir
  dir=$(phase_dir) || return 1
  grep -qiE '^Status:[[:space:]]*READY' "$dir/dev-plan.md" 2>/dev/null
}

# Absolute path of the active feature's module folder: the feature folder's
# parent, or its grandparent in the legacy docs/product/<area>/phases/<phase>/ layout.
module_dir() {
  local dir
  dir=$(phase_dir) || return 1
  dir="${dir%/}"
  [[ "$dir" != "$PROJECT_DIR" ]] || return 1   # line 1 of current-phase is empty
  dir="${dir%/*}"
  [[ "${dir##*/}" == phases ]] && dir="${dir%/*}"
  printf '%s\n' "$dir"
}

# A value from the active feature's .plumbline file (key=value lines, # starts a
# comment). A feature without the file, or without the key, reads as a v0.3 phase:
# profile=full, ux=yes, module=<module folder name>, no surfaces. An unknown key
# prints nothing.
feature_meta() { # key
  local dir v=""
  dir=$(phase_dir) && [[ -f "$dir/.plumbline" ]] && v=$(awk -v k="$1" '
    { gsub(/\r/, ""); sub(/#.*/, ""); i = index($0, "=") }
    !i { next }
    {
      key = substr($0, 1, i - 1); val = substr($0, i + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (key == k) { print val; exit }
    }' "$dir/.plumbline")
  if [[ -z "$v" ]]; then
    case "$1" in
      profile) v=full ;;
      ux) v=yes ;;
      module) v=$(module_dir) && v="${v##*/}" ;;
    esac
  fi
  [[ -n "$v" ]] && printf '%s\n' "$v"
  return 0
}

# Number for the next feature folder, repo-wide: the highest number among
# docs/product/*/<nn>-<slug>/ and legacy docs/product/*/phases/phase-<nn>/, plus 1,
# zero-padded to two digits (01 when there are none).
next_feature_number() {
  local d max=0
  for d in "$PROJECT_DIR"/docs/product/*/[0-9][0-9]*-*/ "$PROJECT_DIR"/docs/product/*/phases/phase-[0-9]*/; do
    [[ -d "$d" ]] || continue   # an unmatched glob stays as written
    d="${d%/}"; d="${d##*/}"; d="${d#phase-}"
    [[ "$d" =~ ^([0-9]+) ]] || continue
    (( 10#${BASH_REMATCH[1]} > max )) && max=$((10#${BASH_REMATCH[1]}))
  done
  printf '%02d\n' $((max + 1))
}

# Data rows of a Markdown table, one per line, cells trimmed and tab-separated.
# With a heading, only tables under the "## <heading>" section; without one, every
# table in the file. Header and separator rows are skipped.
md_table() { # file [heading]
  [[ -f "$1" ]] || return 1
  awk -v h="${2:-}" '
    { sub(/\r$/, "") }
    /^#+ / { if (h != "") sec = (index($0, "## " h) == 1); inrow = 0; next }
    h == "" { sec = 1 }
    !/^\|/ { inrow = 0; next }
    !sec { next }
    {
      if (!inrow) { inrow = 1; next }             # header row of a new table
      if ($0 ~ /^\|[ :|-]+$/) next                 # separator row
      n = split($0, c, "|"); out = ""
      last = (c[n] ~ /^ *$/) ? n - 1 : n
      for (i = 2; i <= last; i++) {
        gsub(/^ +| +$/, "", c[i]); out = out (i > 2 ? "\t" : "") c[i]
      }
      print out
    }' "$1"
}

# Body of a "## <heading>" section (prefix match), without the heading.
section_body() { # file heading
  [[ -f "$1" ]] || return 0
  awk -v h="$2" '{ sub(/\r$/, "") } /^## / { sec = (index($0, "## " h) == 1); next } sec' "$1" \
    | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

# Files anyone may write and nobody owns committing (repo-relative path): the
# phase Q&A log, progress notes, generated briefs and AC lists, QA screenshots,
# diffs, accessibility reports and evidence, and agent memory. The ownership
# guard lets everyone edit them, and the idle gate doesn't count them as anyone's
# uncommitted work.
shared_path() {
  case "$1" in
    */questions.md|*/progress.md|*/briefs/*|*/acceptance-criteria.json) return 0 ;;
    */qa/shots/*|*/qa/diff/*|*/qa/a11y/*|*/qa/evidence/*|*/qa/visual.tsv) return 0 ;;
    .claude/agent-memory/*) return 0 ;;
  esac
  return 1
}

# Space-separated globs a teammate owns, from the dev plan's Ownership table.
owned_globs() {
  local dir who="$1"
  dir=$(phase_dir) || return 1
  [[ -f "$dir/dev-plan.md" ]] || return 1
  md_table "$dir/dev-plan.md" Ownership | awk -F'\t' -v who="$who" '$1 == who { print $2; exit }'
}

# Uncommitted files in the repo (modified, staged or untracked), one repo-relative
# path per line. Handles spaces and renames.
dirty_files() {
  git -C "$PROJECT_DIR" status --porcelain --untracked-files=all 2>/dev/null | tr -d '\r' \
    | cut -c4- | sed -e 's/.* -> //' -e 's/^"\(.*\)"$/\1/'
}

# True if a repo-relative path matches one of the space-separated globs.
matches_globs() { # path globs
  local - g
  set -f   # treat globs as patterns, never expand them against the disk
  for g in $2; do [[ "$1" == $g ]] && return 0; done
  return 1
}

# Teammate name for a hook's agent_id (and agent_type). Tries, in order:
# 1. the team config, when it lists the teammate;
# 2. the agent ID itself: teammates get IDs like aeng-a-e0e49e4975cf862f
#    (a + name + - + 16 hex), while plain subagents get a + hex only;
# 3. agent_type, which is the name for teammates spawned without an agent type.
teammate_name_for() {
  local id="$1" type="${2:-}" dir name=""
  [[ -n "$id" ]] || return 1
  dir="$(norm_path "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")/teams"
  if [[ -d "$dir" ]]; then
    name=$(jqr --arg id "$id" '.members[]? | select(.agentId == $id) | .name' \
      "$dir"/*/config.json 2>/dev/null | head -n1)
  fi
  if [[ -z "$name" && "$id" =~ ^a(.+)-[0-9a-f]{16}$ ]]; then
    name="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$name" && -n "$type" && -n "$(owned_globs "$type")" ]]; then
    name="$type"
  fi
  [[ -n "$name" ]] && printf '%s\n' "$name"
}

# The project profile, docs/product/project.md (dev plan §6.3).
project_file() { printf '%s\n' "$PROJECT_DIR/docs/product/project.md"; }

# Surface names from the profile's Surfaces table, one per line, in table order;
# nothing when there's no profile. A row whose Surface ends in " (check)" is a
# detection hint the user hasn't confirmed, so it's skipped here and in surface_row.
project_surfaces() {
  md_table "$(project_file)" Surfaces 2>/dev/null | awk -F'\t' '$1 != "" && $1 !~ / \(check\)$/ { print $1 }'
}

# The same names on one line, for messages: "api, web-ui".
surface_list() { project_surfaces | paste -sd, - | sed 's/,/, /g'; }

# One surface's row from the profile, cells tab-separated in the table's order:
# Surface, Stack, Paths, Run, Typecheck, Lint, AC tests. Returns 1 when there's no
# profile or no row for that surface.
surface_row() { # surface
  [[ -n "${1:-}" ]] || return 1
  md_table "$(project_file)" Surfaces 2>/dev/null | awk -F'\t' -v s="$1" '
    $1 == s && $1 !~ / \(check\)$/ { print; found = 1; exit }
    END { exit !found }'
}

# The surface whose profile row check_command reads (dev plan §6.8). Prints it, or
# nothing for the legacy defaults: no profile, or no surface and a profile that
# lists none. With no surface, a profile with one row means that row. Returns 1
# for a surface the profile doesn't list (names are exact: API isn't api), 2 for
# no surface when the profile lists several, so the wrong tests never run.
profile_surface() { # surface
  local list
  [[ -f "$(project_file)" ]] || return 0
  list=$(project_surfaces)
  if [[ -z "${1:-}" ]]; then
    [[ "$list" == *$'\n'* ]] && return 2
    [[ -n "$list" ]] && printf '%s\n' "$list"
    return 0
  fi
  grep -qxF -- "$1" <<<"$list" || return 1
  printf '%s\n' "$1"
}

# The message for a profile row whose AC tests cell is empty (check_command's 3).
ac_command_missing() { # surface as given
  printf 'AC tests: no command for surface %s in docs/product/project.md; write one (an adapter, generic, or a command), or none to skip\n' \
    "$(profile_surface "${1:-}")"
}

# The kind of a surface name: one of the ten kinds (dev plan §6.3). A repo with
# two of a kind names the second "<kind>-<name>" (web-ui-shop), so a name may
# extend its kind with "-<name>". Returns 1 for a name that isn't one.
surface_kind() { # surface
  local k
  for k in web-ui mobile-ui desktop-ui api service cli library data ai infra; do
    [[ "${1:-}" == "$k" || "${1:-}" == "$k"-* ]] && { printf '%s\n' "$k"; return 0; }
  done
  return 1
}

# The command for one check, by precedence (dev plan §6.8):
# 1. its env var when set (set to "" skips the check);
# 2. the profile's row for the surface, as profile_surface picks it: the
#    Typecheck, Lint or AC tests cell. "none" skips the check, and so does an
#    empty Typecheck or Lint cell; an empty AC tests cell returns 3, since a pass
#    must mean tests ran. An AC tests cell that is just node, pytest, go or
#    generic, optionally followed by --dir <path> (or --surface <s> for generic),
#    becomes that adapter in ac-tests/ (generic also gets --surface); anything
#    else (node --test, go test ./...) is a raw command;
# 3. the legacy npm default, when there's no profile.
# Returns 1 or 2 as profile_surface does, printing nothing. run_checks appends
# the IDs as one quoted argument, so a command must take them last.
check_command() { # env var name, surface, legacy default
  if [[ -n "${!1+set}" ]]; then printf '%s\n' "${!1}"; return 0; fi
  local surface col row cell name rest dir q opt val re
  case "$1" in
    PLUMBLINE_TYPECHECK) col=5 ;;
    PLUMBLINE_LINT)      col=6 ;;
    PLUMBLINE_TEST_AC)   col=7 ;;
    *) printf '%s\n' "$3"; return 0 ;;
  esac
  surface=$(profile_surface "${2:-}") || return $?
  if [[ -z "$surface" ]] || ! row=$(surface_row "$surface"); then printf '%s\n' "$3"; return 0; fi
  cell=$(awk -F'\t' -v c="$col" '{ print $c }' <<<"$row")
  [[ "$cell" == \`*\` ]] && cell="${cell:1:${#cell}-2}"   # a cell written as `code`
  case "$cell" in [Nn][Oo][Nn][Ee]) printf '\n'; return 0 ;; esac
  if [[ "$col" == 7 ]]; then
    [[ -n "$cell" ]] || return 3
    name="${cell%%[[:space:]]*}"; rest="${cell#"$name"}"
    # The options an adapter takes from the cell, each followed by one shell word
    # (plain, quoted, or both, as detect-project writes an odd folder name).
    opt=--dir; [[ "$name" == generic ]] && opt='--(dir|surface)'
    val="(\\\\.|'[^']*'|\"[^\"]*\"|[^[:space:]'\"\\\\])+"
    re="^([[:space:]]+$opt(=|[[:space:]]+)$val)*[[:space:]]*\$"
    case "$name" in
      node|pytest|go|generic)
        [[ "$rest" =~ $re ]] || { printf '%s\n' "$cell"; return 0; }   # a real command
        # Double-quoted for eval, so a scripts folder with spaces still works.
        dir="${PLUMBLINE_SCRIPTS//\\/\\\\}"; dir="${dir//\"/\\\"}"
        dir="${dir//\$/\\\$}"; dir="${dir//\`/\\\`}"
        printf -v q %q "$surface"
        [[ "$name" == generic && ! "$rest" =~ [[:space:]]--surface ]] && rest=" --surface $q$rest"
        cell="bash \"$dir/ac-tests/$name.sh\"$rest" ;;
    esac
  fi
  printf '%s\n' "$cell"
}

# One check for run_checks, in the repo root; an empty command is skipped. The
# output replaces the log, so on failure the log holds the failing check's output.
run_check() { # label, command
  [[ -n "$2" ]] || return 0
  local t0=$SECONDS
  if ! (cd "$PROJECT_DIR" && eval "$2") >"$RUN_CHECKS_LOG" 2>&1; then
    RUN_CHECKS_FAILED="$1"
    return 1
  fi
  RUN_CHECKS_TIMING="$RUN_CHECKS_TIMING${RUN_CHECKS_TIMING:+ · }$1 $((SECONDS - t0))s"
}

# Typecheck, lint, then the tests named after the given AC IDs, stopping at the
# first failure. Shared by the task gate and ac-check.sh. Each command comes from
# check_command: PLUMBLINE_TYPECHECK, PLUMBLINE_LINT or PLUMBLINE_TEST_AC when set
# (to "" to skip that check), else the surface's row in docs/product/project.md,
# else `npm run -s typecheck`, `npm run -s lint` and `npm run -s test:ac --`, so a
# repo without a profile behaves as in v0.3. The test command gets the IDs as one
# quoted argument; empty IDs skip the tests (a [chore] task). Nothing runs when a
# command can't be chosen. Returns 0 or 1 and leaves, for the caller:
#   RUN_CHECKS_FAILED  the check that failed: typecheck, lint or tests, or surface
#                      when profile_surface refused the surface ("" on a pass)
#   RUN_CHECKS_ERROR   why, when tests failed before any check ran: the
#                      surface's AC tests cell is empty (ac_command_missing)
#   RUN_CHECKS_LOG     temp file with the last check's output; the caller removes it
#   RUN_CHECKS_TIMING  the checks that passed, e.g. "typecheck 12s · lint 4s · tests 9s"
run_checks() { # "<IDs separated by |>" [surface]
  local ids="$1" surface="${2:-}" typecheck lint test_ac="" rc=0
  RUN_CHECKS_FAILED="" RUN_CHECKS_ERROR="" RUN_CHECKS_TIMING="" RUN_CHECKS_LOG=$(mktemp)
  typecheck=$(check_command PLUMBLINE_TYPECHECK "$surface" "npm run -s typecheck") \
    && lint=$(check_command PLUMBLINE_LINT "$surface" "npm run -s lint") \
    || { RUN_CHECKS_FAILED=surface; return 1; }
  if [[ -n "$ids" ]]; then
    test_ac=$(check_command PLUMBLINE_TEST_AC "$surface" "npm run -s test:ac --") || rc=$?
    case "$rc" in
      0) ;;
      3) RUN_CHECKS_FAILED=tests RUN_CHECKS_ERROR=$(ac_command_missing "$surface"); return 1 ;;
      *) RUN_CHECKS_FAILED=surface; return 1 ;;
    esac
  fi
  run_check typecheck "$typecheck" || return 1
  run_check lint "$lint" || return 1
  if [[ -n "$test_ac" ]]; then
    run_check tests "$test_ac \"\$ids\"" || return 1
  fi
  return 0
}

debug_log() {
  [[ -n "${PLUMBLINE_HOOK_DEBUG:-}" ]] && echo "$1" >> "${TMPDIR:-/tmp}/plumbline-hooks.jsonl"
  return 0
}
