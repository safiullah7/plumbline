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
# phase Q&A log, progress notes, generated briefs and AC lists, QA evidence, and
# agent memory. The ownership guard lets everyone edit them, and the idle gate
# doesn't count them as anyone's uncommitted work.
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

# A string as one single-quoted shell word.
sq() { # string
  local q="'" r="'\\''"
  printf "'%s'" "${1//$q/$r}"
}

# An AC tests cell cut into its parts at each standalone + (a word that is just
# +, outside quotes), one per line, blank parts kept. A cell with no such + is
# one part, unchanged. Prints "blank" instead when a part is empty.
ac_cell_parts() { # cell
  local s="$1" i c qt="" cur="" word="" n=${#1} cut=0 parts="" blank=0 p
  for ((i = 0; i <= n; i++)); do
    c="${s:i:1}"
    if [[ -n "$qt" ]]; then
      cur="$cur$c"; word="$word$c"; [[ "$c" == "$qt" ]] && qt=""
    elif [[ "$c" == '\' ]]; then
      cur="$cur$c${s:i+1:1}"; word="$word$c${s:i+1:1}"; i=$((i + 1))
    elif [[ "$c" == "'" || "$c" == '"' ]]; then
      qt="$c"; cur="$cur$c"; word="$word$c"
    elif [[ -z "$c" || "$c" == [[:space:]] ]]; then
      if [[ "$word" == + ]]; then
        cur="${cur%+}"; cut=1; parts="$parts$cur"$'\n'; cur=""
      else
        cur="$cur$c"
      fi
      word=""
    else
      cur="$cur$c"; word="$word$c"
    fi
  done
  if (( ! cut )); then printf '%s\n' "$s"; return 0; fi
  parts="$parts$cur"$'\n'
  while IFS= read -r p; do
    [[ -n "${p//[[:space:]]/}" ]] || blank=1
  done <<<"${parts%$'\n'}"
  (( blank )) && { echo blank; return 0; }
  printf '%s' "$parts"
}

# One AC tests part as a command: a bare adapter name (node, pytest, go,
# playwright, generic) with only --dir (or --surface for generic) options becomes
# that adapter in ac-tests/, anything else is a raw command, returned as written.
ac_part_command() { # part, surface
  local cell="$1" name rest dir q opt val re
  cell="${cell#"${cell%%[![:space:]]*}"}"; cell="${cell%"${cell##*[![:space:]]}"}"
  name="${cell%%[[:space:]]*}"; rest="${cell#"$name"}"
  # The options an adapter takes from the cell, each followed by one shell word
  # (plain, quoted, or both, as detect-project writes an odd folder name).
  opt=--dir; [[ "$name" == generic ]] && opt='--(dir|surface)'
  val="(\\\\.|'[^']*'|\"[^\"]*\"|[^[:space:]'\"\\\\])+"
  re="^([[:space:]]+$opt(=|[[:space:]]+)$val)*[[:space:]]*\$"
  case "$name" in
    node|pytest|go|playwright|generic)
      [[ "$rest" =~ $re ]] || { printf '%s\n' "$cell"; return 0; }   # a real command
      # Double-quoted for eval, so a scripts folder with spaces still works.
      dir="${PLUMBLINE_SCRIPTS//\\/\\\\}"; dir="${dir//\"/\\\"}"
      dir="${dir//\$/\\\$}"; dir="${dir//\`/\\\`}"
      printf -v q %q "$2"
      [[ "$name" == generic && ! "$rest" =~ [[:space:]]--surface ]] && rest=" --surface $q$rest"
      cell="bash \"$dir/ac-tests/$name.sh\"$rest" ;;
  esac
  printf '%s\n' "$cell"
}

# The command for a whole AC tests cell: its one part, or combine.sh over the
# parts of an "A + B" cell. A blank part gives a command that fails with a message.
ac_cell_command() { # cell, surface
  local parts p out="" dir
  parts=$(ac_cell_parts "$1")
  if [[ "$parts" == blank ]]; then
    printf '%s\n' "echo $(sq "AC tests: the cell \"$1\" for surface ${2:-?} in docs/product/project.md has a blank part (a leading, doubled or trailing +); write adapters or commands joined by \" + \"") >&2; false"
    return 0
  fi
  if [[ "$parts" != *$'\n'* ]]; then ac_part_command "$1" "$2"; return 0; fi
  while IFS= read -r p; do
    [[ -n "$p" ]] && out="$out --cmd $(sq "$(ac_part_command "$p" "$2")")"
  done <<<"$parts"
  dir="${PLUMBLINE_SCRIPTS//\\/\\\\}"; dir="${dir//\"/\\\"}"
  dir="${dir//\$/\\\$}"; dir="${dir//\`/\\\`}"
  printf 'bash "%s/ac-tests/combine.sh"%s\n' "$dir" "$out"
}

# The command for one check, by precedence (dev plan §6.8):
# 1. its env var when set (set to "" skips the check);
# 2. the profile's row for the surface, as profile_surface picks it: the
#    Typecheck, Lint or AC tests cell. "none" skips the check, and so does an
#    empty Typecheck or Lint cell; an empty AC tests cell returns 3, since a pass
#    must mean tests ran. An AC tests cell that is just node, pytest, go,
#    playwright or generic, optionally followed by --dir <path> (or --surface <s>
#    for generic), becomes that adapter in ac-tests/ (generic also gets
#    --surface); anything else (node --test, go test ./...) is a raw command.
#    A cell may join several of these with a standalone + outside quotes (node
#    --dir web + playwright --dir web): each part is mapped that way and the whole
#    becomes combine.sh --cmd '<part>' --cmd '<part>', which merges their per-ID
#    reports. A blank part (a leading, doubled or trailing +) is a mistake in the
#    profile: the command printed is one that fails and says so;
# 3. the legacy npm default, when there's no profile.
# Returns 1 or 2 as profile_surface does, printing nothing. run_checks appends
# the IDs as one quoted argument, so a command must take them last.
check_command() { # env var name, surface, legacy default
  if [[ -n "${!1+set}" ]]; then printf '%s\n' "${!1}"; return 0; fi
  local surface col row cell
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
    cell=$(ac_cell_command "$cell" "$surface")
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

# --- Security (dev plan v0.5 §6) ---

# Stdin lines that are filled-in approvals: they start with the given ERE (the
# kind of line, its subject and the dash that leads into the reason), then a
# reason, and end with "(approved by <name>)", with no <placeholder> left, so the
# template's example approves nothing. Any case. Shared by the evidence waivers,
# the security waivers and the risk acceptances. With a second argument "keep" the
# <placeholder> test is left to the caller: a risk acceptance repeats a finding's
# text, which may hold <id> itself, so security_accepted tests only what follows it.
approved_line() { # head ERE [keep]
  tr -d '\r' | { if [[ "${2:-}" == keep ]]; then cat; else grep -v '<[^>]*>'; fi; } \
    | grep -iE "$1[^[:space:]].*\\(approved by [^)]*[^) ][^)]*\\)[[:space:]]*\$"
}

# security.md in the active feature folder (it may not exist).
security_file() {
  local dir
  dir=$(phase_dir) || return 1
  printf '%s\n' "$dir/security.md"
}

# 0, 1 or 2 for none, attacks or independent; -1 for any other token.
security_rank() { # token
  case "${1:-}" in none) echo 0 ;; attacks) echo 1 ;; independent) echo 2 ;; *) echo -1 ;; esac
}

# The two places a level is written, spaces and backticks stripped; nothing when
# the place has none. A dev plan "Security level:" line with no token reads as
# "(blank)". A token security_rank doesn't know is a gap.
security_key_token() {
  local v
  v=$(feature_meta security)
  v="${v//[[:space:]\`]/}"
  [[ -n "$v" ]] && printf '%s\n' "$v"
  return 0
}
security_plan_token() {
  local dir line
  dir=$(phase_dir) || return 0
  line=$(grep -m1 -iE '^Security level:' "$dir/dev-plan.md" 2>/dev/null)
  if [[ -z "$line" ]]; then
    # Only a declaration written some other way: an unknown token, not silence.
    [[ -n "$(security_plan_bad_line)" ]] && echo "(unreadable)"
    return 0
  fi
  line="${line#*:}"; line="${line//[[:space:]\`]/}"
  printf '%s\n' "${line:-(blank)}"
}
# The first dev plan line that declares a Security level the strict parser above
# doesn't accept: its first words, after any of - > * _ and spaces, are "security
# level" and then a colon (**Security level:** x, - Security level: x, an indented
# one). A mention mid-sentence is not one. Nothing when there is none.
security_plan_bad_line() {
  local dir
  dir=$(phase_dir) || return 0
  tr -d '\r' < "$dir/dev-plan.md" 2>/dev/null \
    | grep -iE '^[-*>_[:space:]]*security[[:space:]]+level[*_[:space:]]*:' | grep -viE '^Security level:' | head -n 1
  return 0
}

# The recorded level: the higher of .plumbline's security= and the dev plan's
# "Security level:" line; none when neither is there. An unknown token counts as
# attacks, so the checks run and the token itself is a gap.
security_level() {
  local best=0 t r
  for t in "$(security_key_token)" "$(security_plan_token)"; do
    [[ -n "$t" ]] || continue
    case "$t" in none) r=0 ;; independent) r=2 ;; *) r=1 ;; esac
    (( r > best )) && best=$r
  done
  [[ -n "$(security_plan_bad_line)" ]] && (( best < 1 )) && best=1
  case "$best" in 0) echo none ;; 1) echo attacks ;; *) echo independent ;; esac
}

# The parts the user has waived in security.md, one per line: a filled-in
# "Security waived: <attacks|independent> - <reason> (approved by <name>)".
security_waived_parts() {
  local f
  f=$(security_file) && [[ -f "$f" ]] || return 0
  approved_line '^Security waived:[[:space:]]*(attacks|independent)[[:space:]]*(-|—|:)[[:space:]]*' < "$f" \
    | awk '{ sub(/^[^:]*:[ \t]*/, ""); sub(/[^A-Za-z].*/, ""); print tolower($0) }'
}

# True when the part (attacks or independent) is waived.
security_part_waived() { # part
  security_waived_parts | grep -qx "$1"
}

# The parts of the recorded level the user hasn't waived, on one line: attacks,
# independent, both ("attacks independent"), or none. independent includes attacks.
# The level may be passed in when the caller has it.
security_required() { # [level]
  local lvl="${1:-}" parts="" p out="" waived
  [[ -n "$lvl" ]] || lvl=$(security_level)
  case "$lvl" in attacks|independent) parts=attacks ;; esac
  [[ "$lvl" == independent ]] && parts="$parts independent"
  waived=" $(security_waived_parts | paste -sd' ' -) "
  for p in $parts; do [[ "$waived" == *" $p "* ]] || out="$out${out:+ }$p"; done
  echo "${out:-none}"
}

# Rows of one security table: plan (the dev plan's ## Attack plan), own or
# findings (security.md's ## Own attacks and ## Findings). Each output line is
# "row" or "gap", then the cells or the message, joined by the unit separator
# (0x1f; a tab would merge empty cells in read). Unlike md_table, the header must
# be exact and every | line up to the next # or ## heading is counted (### and
# deeper headings stay inside the section, and each table under them is read the
# same way): a row after a blank or text line, a | line that belongs to no table,
# a row with the wrong cell count (a | in a cell), a bad SEC ID or severity, a
# missing section or header is a gap, so nothing is dropped silently. Returns 1,
# printing nothing, when the file doesn't exist.
security_rows() { # plan|own|findings
  local dir file h hdr
  dir=$(phase_dir) || return 1
  case "${1:-}" in
    plan)     file="$dir/dev-plan.md"; h="Attack plan"; hdr="SEC ID|Surface|Attack|Must happen|Checked" ;;
    own)      file="$dir/security.md"; h="Own attacks"; hdr="SEC ID|Surface|Attack|Must happen" ;;
    findings) file="$dir/security.md"; h="Findings"; hdr="#|Severity|Finding|Status|Evidence" ;;
    *) return 1 ;;
  esac
  [[ -f "$file" ]] || return 1
  awk -v h="$h" -v hdr="$hdr" -v kind="$1" -v file="${file##*/}" '
    function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
    function gap(m) { printf "gap%s%s\n", US, m }
    function ishdr(l,    k, m, c2, ok) {
      m = split(l, c2, "|")
      ok = (m - 2 == ncol && c2[1] == "" && c2[m] == "")
      for (k = 1; ok && k <= ncol; k++) if (trim(c2[k + 1]) != want[k]) ok = 0
      return ok
    }
    # A blank or text line, or a ### heading, ends the table being read.
    function endtable() {
      if (state == 1) gap(file " line " NR ": the table under ## " h " has a header but no separator row")
      if (state == 1 || state == 2 || state == 9) state = 3
    }
    BEGIN { US = "\037"; ncol = split(hdr, want, "|"); state = 0 }
    { sub(/\r$/, "") }
    /^#+([ \t]|$)/ {
      match($0, /^#+/)
      if (RLENGTH >= 3) { if (insec) { endtable(); if (state == 3) state = 0 } next }   # ### and deeper stay in the section
      insec = (trim($0) == "## " h); if (insec) found = 1; next
    }
    !insec { next }
    trim($0) !~ /^\|/ { endtable(); next }
    {
      line = trim($0); anytable = 1
      if (state == 3) {
        if (ishdr(line)) { state = 1; next }     # another table, with the same exact header
        gap(file " line " NR ": a table row after a blank or text line; the table under ## " h " is split"); next
      }
      if (state == 9) next
      if (state == 1) {
        if (line ~ /^\|[ :|-]+$/) { state = 2; next }
        gap(file " line " NR ": no separator row under the header of ## " h); state = 9; next
      }
      n = split(line, c, "|"); cells = n - 2
      if (state == 0) {
        if (ishdr(line)) { state = 1; next }
        gap(file " line " NR ": the table under ## " h " must have the header | " hdr " |"); state = 9; next
      }
      if (c[1] != "" || c[n] != "") { gap(file " line " NR ": a table row must start and end with |"); next }
      if (cells != ncol) { gap(file " line " NR ": " cells " cells, expected " ncol " (a | inside a cell?)"); next }
      for (i = 2; i < n; i++) { c[i] = trim(c[i]); gsub(/\t/, " ", c[i]) }
      if (kind != "findings" && c[2] !~ /^SEC-[0-9]+-[0-9]+$/) { gap(file " line " NR ": \"" c[2] "\" is not a SEC ID (SEC-<nn>-<nnn>)"); next }
      if (kind == "findings" && tolower(c[3]) !~ /^(critical|high|medium|low)$/) { gap(file " line " NR ": severity \"" c[3] "\" is not critical, high, medium or low"); next }
      if (kind == "findings") { c[3] = tolower(c[3]); c[5] = tolower(c[5]) }   # severity and status read in any case
      out = "row"
      for (i = 2; i < n; i++) out = out US c[i]
      print out
    }
    END {
      if (!found) gap(file " has no \"## " h "\" section")
      else if (!anytable) gap(file ": ## " h " has no table with the header | " hdr " |")
      else if (state == 1) gap(file ": the last table under ## " h " has a header but no separator row")
    }' "$file"
}

# The "Independent pass:" value in security.md, e.g. "not started" or "complete (round 2)".
security_independent_state() {
  local f
  f=$(security_file) && [[ -f "$f" ]] || return 0
  awk 'tolower(substr($0, 1, 17)) == "independent pass:" { sub(/\r$/, ""); sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$f"
}

# A string with whitespace squeezed and trimmed, and lower-cased when the second
# argument is 1, for comparing what the user accepted with what a row says.
security_squeeze() { # string [fold]
  local s
  s=$(printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')
  [[ "${2:-}" == 1 ]] && s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$s"
}

# True when security.md holds a filled-in "Risk accepted: <subject> - <reason>
# (approved by <name>)" whose text starts with the subject (whitespace squeezed;
# case too when fold is 1), then a dash or colon. A longer subject, or a row edited
# since, is not covered. The subject is the row's own text and may hold <id> or a
# path with a <; only what follows it (the reason and the approval) must be free of
# <placeholders>.
security_accepted() { # subject fold
  local f line body want re='^([[:space:]]+(-|—)|[[:space:]]*:)[[:space:]]*[^[:space:]]'
  f=$(security_file) && [[ -f "$f" ]] || return 1
  want=$(security_squeeze "$1" "$2")
  while IFS= read -r line; do
    body=$(security_squeeze "${line#*:}" "$2")
    [[ "$body" == "$want"* ]] || continue
    body="${body#"$want"}"
    grep -q '<[^>]*>' <<<"$body" && continue
    [[ "$body" =~ $re ]] && return 0
  done < <(approved_line '^Risk accepted:[[:space:]]*' keep < "$f")
  return 1
}

# The commit the feature branched from: the merge base of HEAD with
# $PLUMBLINE_BASE_REF when set (and only that), else with the target of
# origin/HEAD, else main, else master. Returns 1 when there is none.
secrets_base() {
  local ref t
  if [[ -n "${PLUMBLINE_BASE_REF:-}" ]]; then
    git -C "$PROJECT_DIR" merge-base HEAD "$PLUMBLINE_BASE_REF" 2>/dev/null
    return
  fi
  t=$(git -C "$PROJECT_DIR" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)
  for ref in "$t" main master; do
    [[ -n "$ref" ]] && git -C "$PROJECT_DIR" merge-base HEAD "$ref" 2>/dev/null && return 0
  done
  return 1
}

# Secret-looking additions on the branch since its base: "<path>:<line>" for each
# added line holding a private-key block, an AWS key ID, a Stripe live secret key,
# a GitHub token or a Slack bot token, and "<path>:1" for each added .env file
# other than .env.example, .env.sample and .env.template. Narrow on purpose:
# removed lines, publishable keys and the word "password" never hit. Returns 2,
# printing nothing, when there is no base to compare with.
secrets_scan() {
  local base re
  base=$(secrets_base) || return 2
  re='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|sk_live_[0-9A-Za-z]{10,}|ghp_[0-9A-Za-z]{30,}|xoxb-[0-9A-Za-z-]{10,}'
  {
    git -C "$PROJECT_DIR" -c core.quotepath=false diff --no-color --no-ext-diff -U0 "$base" HEAD 2>/dev/null | tr -d '\r' | awk '
      /^diff --git / { inh = 0; next }
      !inh && /^\+\+\+ / { f = substr($0, 5); if (f == "/dev/null") f = ""; else { sub(/^b\//, "", f); sub(/\t.*$/, "", f) }; next }
      /^@@/ { match($0, /\+[0-9]+/); ln = substr($0, RSTART + 1, RLENGTH - 1) + 0; inh = 1; next }
      inh && /^\+/ { if (f != "") printf "%s\t%d\t%s\n", f, ln, substr($0, 2); ln++ }' \
      | grep -E -e "$re" | cut -f1,2 | tr '\t' ':'
    git -C "$PROJECT_DIR" -c core.quotepath=false diff --name-only --diff-filter=ACR "$base" HEAD 2>/dev/null | tr -d '\r' \
      | awk '{ n = $0; sub(/^.*\//, "", n); n = tolower(n)
          if (n == ".env.example" || n == ".env.sample" || n == ".env.template") next
          if (n == ".env" || substr(n, 1, 5) == ".env.") print $0 ":1" }'
  } | awk '!seen[$0]++'
  return 0
}

# Runs one surface's attack tests through ac-check.sh (typecheck and lint skipped)
# and prints a gap for each ID that doesn't print "<ID>: pass", or one gap for the
# surface when the run couldn't start. With SECURITY_RESULTS_FILE set, each ID's
# result is also appended to it as "<ID>, <surface>, <result>[, <note>]" (unit
# separator); a note is something the report says that isn't a gap. Two cases:
#   - the generic adapter prints no per-ID lines, only a "generic:" warning, and
#     ac-check exits 0 when its command does: every ID of that run passes by exit
#     status (a non-zero exit with no ID lines stays a gap);
#   - the third argument lists the attacker's own attacks, one "<ID>" or
#     "<ID><US><finding>" per line. The attacker writes each so it fails while the
#     hole is open, so a failing one that a finding covers (<finding>) is a note,
#     and one nothing covers is a gap that says to record a finding or fix it.
security_run() { # surface "<ID>|<ID>" ["<own attack lines>"]
  local s="$1" ids="$2" owns="${3:-}" out rc id line re ctx args seen=0 US=$'\037' label own cover nt hint
  label="${s:-the default surface}"
  if [[ -n "$s" ]]; then
    profile_surface "$s" >/dev/null; rc=$?
    if (( rc == 1 )); then
      echo "surface \"$s\" (for ${ids//|/ }) isn't in docs/product/project.md's Surfaces table; the profile lists: $(surface_list)"
      return 0
    fi
  fi
  if [[ ! -f "$PLUMBLINE_SCRIPTS/ac-check.sh" ]]; then
    echo "attack tests for ${ids//|/ } could not run: ac-check.sh is missing from $PLUMBLINE_SCRIPTS"
    return 0
  fi
  args=("$ids"); [[ -n "$s" ]] && args+=(--surface "$s")
  out=$(cd "$PROJECT_DIR" && PLUMBLINE_TYPECHECK= PLUMBLINE_LINT= CLAUDE_PROJECT_DIR="$PROJECT_DIR" \
    bash "$PLUMBLINE_SCRIPTS/ac-check.sh" "${args[@]}" 2>&1); rc=$?
  out=$(tr -d '\r' <<<"$out")
  # Why a run gave nothing: ac-check's own first line when it failed, else the last line.
  if (( rc != 0 )); then
    ctx=$(grep -m1 '^ac-check:' <<<"$out")
    [[ -n "$ctx" ]] || ctx=$(grep . <<<"$out" | tail -n 1)
  fi
  for id in ${ids//|/ }; do grep -qE "^$id: " <<<"$out" && seen=1; done
  if (( ! seen )); then
    if (( rc == 0 )) && grep -q '^generic: ' <<<"$out"; then
      for id in ${ids//|/ }; do
        [[ -n "${SECURITY_RESULTS_FILE:-}" ]] && printf '%s%s%s%s%s%s%s\n' "$id" "$US" "$s" "$US" "pass (exit status)" "$US" "$id: generic runner: passed by exit status" >> "$SECURITY_RESULTS_FILE"
      done
      return 0
    fi
    for id in ${ids//|/ }; do
      [[ -n "${SECURITY_RESULTS_FILE:-}" ]] && printf '%s%s%s%sno result\n' "$id" "$US" "$s" "$US" >> "$SECURITY_RESULTS_FILE"
    done
    echo "attack tests for ${ids//|/ } on $label gave no results (ac-check exit $rc): ${ctx:-no output}"
    return 0
  fi
  for id in ${ids//|/ }; do
    line=$(grep -m1 -E "^$id: " <<<"$out")
    own=$(awk -F"$US" -v id="$id" '$1 == id { print 1; exit }' <<<"$owns")
    cover=$(awk -F"$US" -v id="$id" '$1 == id { print $2; exit }' <<<"$owns")
    re="^$id: fail"
    nt=""; [[ -n "$own" && -n "$cover" && "$line" =~ $re ]] && nt="$id fails: $cover"
    [[ -n "${SECURITY_RESULTS_FILE:-}" ]] && printf '%s%s%s%s%s%s\n' "$id" "$US" "$s" "$US" "${line:+${line#"$id: "}}" "${nt:+$US$nt}" >> "$SECURITY_RESULTS_FILE"
    re="^$id: pass( |\(|\$)"
    [[ "$line" =~ $re ]] && continue
    [[ -n "$nt" ]] && continue
    if [[ -n "$line" ]]; then
      hint=""; re="^$id: fail"
      [[ -n "$own" && "$line" =~ $re ]] && hint=" (own attack: record a finding in security.md that names $id, or fix it)"
      echo "attack test did not pass on $label: $line$hint"
    else
      echo "attack test $id gave no result on $label (ac-check exit $rc)${ctx:+: $ctx}"
    fi
  done
}

# Every security gap of the active feature, one per line; nothing when the recorded
# level is none (the v0.4b path: no new check, no test run). The rules are dev plan
# v0.5 §6.4.4. It reads documents and git, and runs the attack tests through
# security_run unless --no-run. security-check.sh and signoff-check.sh both call it.
security_gaps() { # [--no-run]
  local run=1 dir sec plan lvl req kt pt kr pr US=$'\037' pairs="" nplan=0 gapped=0 profile=""
  local kind a b c d e id surf chk desc n sev txt st hit hits rc s ids bad planids="" ownids="" excuses="" ownmap="" note named
  [[ "${1:-}" == --no-run ]] && run=0
  dir=$(phase_dir) || return 0
  kt=$(security_key_token); pt=$(security_plan_token); bad=$(security_plan_bad_line)
  case "$kt" in "") kr=0 ;; none) kr=0 ;; attacks) kr=1 ;; independent) kr=2 ;; *) kr=-1 ;; esac
  case "$pt" in "") pr=0 ;; none) pr=0 ;; attacks) pr=1 ;; independent) pr=2 ;; "(unreadable)") pr=0 ;; *) pr=-1 ;; esac
  # The recorded level, as security_level works it out from the same two tokens.
  lvl=none
  (( kr < 0 || pr < 0 )) && lvl=attacks
  (( kr == 1 || pr == 1 )) && lvl=attacks
  (( kr == 2 || pr == 2 )) && lvl=independent
  [[ -n "$bad" && "$lvl" == none ]] && lvl=attacks   # a declaration we can't read counts as attacks
  [[ "$lvl" == none ]] && return 0
  sec="$dir/security.md"; plan="$dir/dev-plan.md"
  [[ -f "$PROJECT_DIR/docs/product/project.md" ]] && profile=1

  (( kr < 0 )) && echo "unknown security level \"$kt\" in .plumbline security= (use none, attacks or independent)"
  (( pr < 0 )) && echo "unknown security level \"$pt\" on the Security level: line in dev-plan.md (use none, attacks or independent)"
  [[ -n "$bad" ]] && echo "Security level line in dev-plan.md can't be read: $(security_squeeze "$bad"); write \`Security level: <attacks|independent>\` on its own line"
  (( pr > kr && kr >= 0 )) && echo "raise not recorded: dev-plan.md says Security level: $pt but .plumbline says ${kt:-nothing}; run kickoff.sh --set-security $pt"
  [[ -f "$sec" ]] || echo "security.md is missing; run kickoff.sh --set-security $lvl to create it"

  req=$(security_required "$lvl")

  # The lead's attack plan: its rows, the reviewer's verdict, and what to run.
  if [[ " $req " == *" attacks "* ]]; then
    if [[ ! -f "$plan" ]]; then
      echo "dev-plan.md is missing, so there is no attack plan"
    else
      while IFS=$US read -r kind a b c d e; do
        if [[ "$kind" == gap ]]; then echo "$a"; gapped=1; continue; fi
        nplan=$((nplan + 1)); id="$a"; surf="$b"; chk="$e"; planids="$planids $id "
        desc=empty; [[ -n "$chk" ]] && desc="\"$chk\""
        case "$chk" in
          [Mm][Aa][Tt][Cc][Hh][Ee][Ss]*) ;;
          *) echo "attack $id: Checked is $desc, not matches (dev-plan.md ## Attack plan)" ;;
        esac
        if [[ -n "$profile" && -z "$surf" ]]; then
          echo "attack $id has no Surface (dev-plan.md ## Attack plan)"
        else
          pairs="$pairs${profile:+$surf}$US$id"$'\n'
        fi
      done < <(security_rows plan)
      (( nplan == 0 && gapped == 0 )) && echo "the attack plan has no rows (dev-plan.md ## Attack plan)"
    fi
  fi

  if [[ -f "$sec" ]]; then
    # The attacker's own attacks run like the plan's, whenever any part is required.
    while IFS=$US read -r kind a b c d e; do
      if [[ "$kind" == gap ]]; then echo "$a"; continue; fi
      [[ "$req" == none ]] && continue
      id="$a"; surf="$b"
      # The plan's IDs are strict: a failing one is always a gap. Only an own attack can be covered.
      [[ "$planids" == *" $id "* ]] || ownids="$ownids $id "
      if [[ -n "$profile" && -z "$surf" ]]; then
        echo "own attack $id has no Surface (security.md ## Own attacks)"
      else
        pairs="$pairs${profile:+$surf}$US$id"$'\n'
      fi
    done < <(security_rows own)

    # A critical or high finding stays open until it is verified or the user accepts it.
    # Each own attack is written to fail while its hole is open, so a failing one is not
    # a gap when a finding naming it (in its Finding or Evidence cell) covers it: a
    # medium or low finding, or a critical or high one the user accepted. A verified
    # finding covers nothing (the fix is claimed, so the test must pass). An open
    # critical or high finding is a gap of its own; the failing test is only noted.
    while IFS=$US read -r kind a b c d e; do
      if [[ "$kind" == gap ]]; then echo "$a"; continue; fi
      n="${a#\#}"; sev="$b"; txt="$c"; st="$d"   # security_rows lowercases severity and status
      note=""
      if [[ "$sev" == critical || "$sev" == high ]]; then
        if [[ "$st" == verified ]]; then :
        elif security_accepted "#$n $sev $txt" 1; then note="finding #$n (accepted)"
        else
          note="finding #$n ($sev, open; its own gap)"
          echo "open $sev finding #$n: $txt (security.md); have it fixed and verified, or ask the user to accept the risk"
        fi
      elif [[ "$st" != verified ]]; then
        note="finding #$n ($sev)"
      fi
      [[ -n "$note" ]] || continue
      for named in $(grep -oE 'SEC-[0-9]+-[0-9]+' <<<"$txt $e" | sort -u); do
        [[ "$ownids" == *" $named "* && "$excuses" != *"$named$US"* ]] && excuses="$excuses$named$US$note"$'\n'
      done
    done < <(security_rows findings)
    for named in $ownids; do ownmap="$ownmap$named$US$(awk -F"$US" -v id="$named" '$1 == id { print $2; exit }' <<<"$excuses")"$'\n'; done

    if [[ " $req " == *" independent "* ]]; then
      st=$(security_independent_state)
      [[ "$st" =~ ^[Cc]omplete[[:space:]]*\(round[[:space:]]+[0-9]+\)$ ]] || echo "the independent pass is ${st:-missing}, not complete (security.md Independent pass:)"
    fi
  fi

  # Committed secrets, unless the user accepted that path.
  hits=$(secrets_scan); rc=$?
  if (( rc == 2 )); then
    echo "secrets scan could not run: no base branch to compare with (PLUMBLINE_BASE_REF, origin/HEAD, main or master)"
  else
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      security_accepted "secret ${hit%:*}" 0 && continue
      echo "secret-looking $hit; remove it, or ask the user to accept it with a Risk accepted: secret ${hit%:*} line"
    done <<<"$hits"
  fi

  # The attack tests, per surface.
  if (( run )) && [[ -n "$pairs" ]]; then
    while IFS= read -r s; do
      ids=$(awk -F"$US" -v s="$s" '$2 != "" && $1 == s { print $2 }' <<<"$pairs" | sort -u | paste -sd'|' -)
      [[ -n "$ids" ]] && security_run "$s" "$ids" "$ownmap"
    done < <(awk -F"$US" 'NF > 1 { print $1 }' <<<"$pairs" | sort -u)
  fi
  return 0
}

debug_log() {
  [[ -n "${PLUMBLINE_HOOK_DEBUG:-}" ]] && echo "$1" >> "${TMPDIR:-/tmp}/plumbline-hooks.jsonl"
  return 0
}
