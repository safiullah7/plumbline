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

PROJECT_DIR=$(norm_path "${CLAUDE_PROJECT_DIR:-$(pwd)}")

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

debug_log() {
  [[ -n "${PLUMBLINE_HOOK_DEBUG:-}" ]] && echo "$1" >> "${TMPDIR:-/tmp}/plumbline-hooks.jsonl"
  return 0
}
