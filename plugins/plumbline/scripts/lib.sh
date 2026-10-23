#!/usr/bin/env bash
# Shared helpers for the Plumbline hooks. Runs in bash on macOS and Linux, and in
# Git Bash on Windows.

# Forward slashes, and /c/... instead of C:\... on Windows, so paths compare.
norm_path() {
  local p="${1//\\//}"
  if command -v cygpath >/dev/null 2>&1; then
    p=$(cygpath -u "$p" 2>/dev/null || printf '%s' "$p")
  fi
  printf '%s\n' "${p%/}"
}

PROJECT_DIR=$(norm_path "${CLAUDE_PROJECT_DIR:-$(pwd)}")

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

# True once the lead has marked the dev plan "Status: READY".
# Gates are enforced only from then on, so discovery and planning run freely.
build_active() {
  local dir
  dir=$(phase_dir) || return 1
  grep -qiE '^Status:[[:space:]]*READY' "$dir/dev-plan.md" 2>/dev/null
}

# Space-separated globs a teammate owns, from the dev plan's Ownership table.
owned_globs() {
  local dir plan who="$1"
  dir=$(phase_dir) || return 1
  plan="$dir/dev-plan.md"
  [[ -f "$plan" ]] || return 1
  awk -v who="$who" '
    { sub(/\r$/, "") }
    /^## / { own = ($0 ~ /^## Ownership/); next }
    own && /^\|/ {
      split($0, c, "|"); name = c[2]; globs = c[3]
      gsub(/^ +| +$/, "", name); gsub(/^ +| +$/, "", globs)
      if (name == who) { print globs; exit }
    }' "$plan"
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
