#!/usr/bin/env bash
# PreToolUse (Edit/Write): during Build, a teammate may only edit files it owns
# in the dev plan's Ownership table. Exit 2 = block + feedback.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

build_active || exit 0
require_jq
file=$(jqr '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
agent_id=$(jqr '.agent_id // empty' <<<"$input")
agent_type=$(jqr '.agent_type // empty' <<<"$input")
[[ -z "$file" || -z "$agent_id" ]] && exit 0      # the lead's own session, or no path
file=$(norm_path "$file")
[[ "$file" != "$PROJECT_DIR"/* ]] && exit 0       # scratch files outside the repo

who=$(teammate_name_for "$agent_id" "$agent_type")
[[ -z "$who" ]] && exit 0                         # a plain subagent, not a teammate

rel="${file#"$PROJECT_DIR"/}"
shared_path "$rel" && exit 0                      # everyone may log Q&A and memory

globs=$(owned_globs "$who")
if [[ -z "$globs" ]]; then
  echo "Ownership guard: '$who' has no row in the dev plan's Ownership table. Ask the lead to add one." >&2
  exit 2
fi

set -f
for g in $globs; do [[ "$rel" == $g ]] && exit 0; done
echo "Ownership guard: $who does not own $rel (owns: $globs). Message the owner or the lead." >&2
exit 2
