#!/usr/bin/env bash
# PreToolUse (Edit/Write/MultiEdit/NotebookEdit). Two locks apply to any agent
# (teammate or plain subagent, whether or not the plan is READY); the main session
# is always allowed:
#   - .plumbline is feature metadata written by kickoff.sh, never by an agent;
#   - a waiver line ("Evidence waived:", "Accessibility waived:") can only come
#     from the user, through the lead's main session.
# During Build, a teammate may also only edit files it owns in the dev plan's
# Ownership table. Exit 2 = block + feedback.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

if ! command -v jq >/dev/null 2>&1; then
  build_active && require_jq                      # the locks need jq: only a running build insists on it
  exit 0
fi
file=$(jqr '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
agent_id=$(jqr '.agent_id // empty' <<<"$input")
agent_type=$(jqr '.agent_type // empty' <<<"$input")
[[ -z "$agent_id" ]] && exit 0                    # the lead's own session

if [[ "${file//\\//}" == */.plumbline ]]; then
  echo "Plumbline: .plumbline is feature metadata written by kickoff.sh; ask the lead or the user to change it." >&2
  exit 2
fi

# A real waiver line starts the line (after spaces and an optional "- "); a mention
# mid-sentence, or a template placeholder, is not one.
new_text=$(jqr '[.tool_input.content, .tool_input.new_string, .tool_input.new_source, (.tool_input.edits[]? | .new_string)]
  | map(select(type == "string")) | .[]' <<<"$input")
if grep -iE '^[[:space:]]*(-[[:space:]]+)?(Evidence|Accessibility) waived:' <<<"$new_text" \
    | grep -qviE '<(reason|kind|surface|who|name)>'; then
  echo "Only the user can approve a waiver. Tell the lead which evidence is missing and why; the build skill will ask the user." >&2
  exit 2
fi

build_active || exit 0
[[ -z "$file" ]] && exit 0                        # no path
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
