#!/usr/bin/env bash
# SessionStart (the lead) and SubagentStart (teammates and Plumbline agents):
# hand over the context each would otherwise go looking for: the active phase
# and plan status, its own Ownership row and brief, escalations, and the answered
# questions that involve it. Claude Code de-duplicates it and re-adds it after
# compaction. Never blocks: on any problem it prints nothing and exits 0.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"
command -v jq >/dev/null 2>&1 || exit 0
dir=$(phase_dir) || exit 0
[[ -d "$dir" ]] || exit 0

event=$(jqr '.hook_event_name // empty' <<<"$input")
[[ "$event" == SessionStart || "$event" == SubagentStart ]] || exit 0
who="" globs=""
if [[ "$event" == SubagentStart ]]; then
  agent_type=$(jqr '.agent_type // empty' <<<"$input")
  who=$(teammate_name_for "$(jqr '.agent_id // empty' <<<"$input")" "$agent_type")
  globs=$(owned_globs "$who" 2>/dev/null)
  # Explore, Plan and other helpers don't need phase context.
  [[ -n "$globs" || "$agent_type" == plumbline:* ]] || exit 0
  [[ -n "$globs" ]] || who=""
fi

rel=$(phase_rel)
status=$(plan_status)
q="$dir/questions.md"
ctx="Plumbline phase: $rel (dev plan: ${status:-not written yet})."
if [[ -n "$who" ]]; then
  ctx+=$'\n'"You are $who. You own: $globs"
  [[ -f "$dir/briefs/$who.md" ]] && ctx+=$'\n'"Your brief: $rel/briefs/$who.md. Read it before anything else; open the full docs only when it isn't enough."
fi
if [[ -f "$q" ]]; then
  open=$(md_table "$q" | awk -F'\t' 'toupper($6) == "OPEN"' | grep -c .)
  esc=$(md_table "$q" | awk -F'\t' 'toupper($6) == "ESCALATED"')
  ctx+=$'\n'"Questions in $rel/questions.md: $open open, $(grep -c . <<<"$esc") escalated to the user."
  if [[ -n "$esc" ]]; then
    ctx+=$'\n'"Escalated (blocks those items until the user answers):"
    ctx+=$'\n'"$(awk -F'\t' '{ printf "- #%s %s\n", $1, substr($4, 1, 200) }' <<<"$esc" | head -n 5)"
  fi
  if [[ -n "$who" ]]; then
    mine=$(md_table "$q" | awk -F'\t' -v w="$who" 'toupper($6) == "ANSWERED" && ($2 == w || $3 == w) { printf "- Q: %s A: %s\n", substr($4, 1, 160), substr($5, 1, 200) }' | tail -n 10)
    [[ -n "$mine" ]] && ctx+=$'\n'"Already answered for you (don't ask again):"$'\n'"$mine"
  fi
fi
[[ -z "$who" && "$event" == SessionStart ]] && ctx+=$'\n'"Run /plumbline:status for coverage, bugs and uncommitted work."

ctx=$(head -n 60 <<<"$ctx" | head -c 9000)
jq -n --arg e "$event" --arg c "$ctx" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
