#!/usr/bin/env bash
# TeammateIdle: a teammate can't go idle with uncommitted changes in files it owns.
# It pushes back at most twice for the same set of files, then lets the teammate
# stop, so a teammate that can't fix it never loops forever. A hook can't message
# the lead, so giving up logs an ESCALATED row in the phase's questions.md, which
# /plumbline:signoff won't pass.
#
# With a clean tree it also checks the team's shared task list (the payload's
# team_name, tasks at <config dir>/tasks/<team_name>/): an engineer with a task
# ready (in progress, or pending with every blocker completed) can't go idle. It is
# refused up to six times for the same open tasks at the same commit (a new commit
# is progress and starts the count again), then let go with a systemMessage (safety
# valve). A task stall writes no questions.md row: nothing would clear it and it
# would block signoff. A refusal (exit 2) speaks on stderr only; a systemMessage
# goes to the user and is printed on exit-0 paths only.
# The lead (teammate_name "lead", no Ownership row) is refused the same way while a
# member of the team has a ready task and none in progress; an owner who isn't a
# member yet (setup, before the spawns) is not counted. No team_name, no task
# folder or no jq output means no task check at all.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

# Append one ESCALATED row for the lead to questions.md, once per set of files.
# Creates the file with the template header if it's missing, numbers the row
# after the highest existing one, and keeps the file's line endings. The optional
# fourth argument replaces the sentence after the teammate's name.
escalate() {
  local who="$1" files="$2" sig="$3" what="${4:-}" dir q n nl=$'\n'
  [[ -n "$what" ]] || what="stopped after two reminders with uncommitted changes in files it owns: $files. Commit them or decide who should."
  dir=$(phase_dir) || return 0
  q="$dir/questions.md"
  grep -q "idle-gate $sig" "$q" 2>/dev/null && return 0
  if [[ ! -f "$q" ]]; then
    local ph title; ph=$(basename "$dir")
    # Legacy phase-NN folders keep "# Phase NN questions"; others use the folder name.
    if [[ "$ph" =~ ^phase-([0-9]+)$ ]]; then title="Phase ${BASH_REMATCH[1]}"; else title="$ph"; fi
    printf '%s\n' "# $title questions" "" \
      "Status values: OPEN, ANSWERED, ESCALATED (needs the user; blocks the item)." "" \
      "| # | From | To | Question | Answer | Status |" \
      "| --- | --- | --- | --- | --- | --- |" > "$q"
  fi
  grep -q $'\r$' "$q" && nl=$'\r\n'
  n=$(awk -F'|' '{ gsub(/[ \r]/, "", $2) } $2 ~ /^[0-9]+$/ && $2 + 0 > m { m = $2 + 0 } END { print m + 1 }' "$q")
  [[ -s "$q" && -n "$(tail -c1 "$q")" ]] && printf '%s' "$nl" >> "$q"
  printf '| %s | hooks | lead | %s %s (idle-gate %s) | | ESCALATED |%s' \
    "$n" "$who" "$what" "$sig" "$nl" >> "$q"
}

# How many times in a row this signature has been seen: the count lives in the state
# file as "<signature> <count>" and starts over when the signature changes.
repeat_count() { # state file, signature
  local prev_sig="" count=0
  [[ -f "$1" ]] && read -r prev_sig count < "$1"
  if [[ "$prev_sig" == "$2" ]]; then count=$((count + 1)); else count=1; fi
  echo "$2 $count" > "$1"
  echo "$count"
}

build_active || exit 0
require_jq
who=$(jqr '.teammate_name // empty' <<<"$input")
session=$(jqr '.session_id // empty' <<<"$input")
team=$(jqr '.team_name // empty' <<<"$input")
tdir=""; [[ -n "$team" ]] && tdir=$(team_dir_for "$team")
state="$(norm_path "${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}")/plumbline-idle"
key="$state/${session:-none}-${who//[^A-Za-z0-9_-]/_}"

# The lead has no Ownership row. It may not idle while an engineer has a ready task
# and none in progress: nobody is on it and only the lead can wake them.
if [[ -n "$tdir" && "$who" == lead ]]; then
  waiting=""
  members=$(team_members "$team")
  while IFS= read -r owner; do
    [[ -n "$owner" && "$owner" != lead && "$owner" != team-lead ]] || continue
    # An owner that isn't on the team yet (setup, before the spawns) isn't waiting.
    grep -qxF -- "$owner" <<<"$members" || continue
    ready=$(ready_tasks "$tdir" "$owner")
    [[ -n "$ready" ]] && ! grep -q $'\tin_progress\t' <<<"$ready" || continue
    first=$(awk -F'\t' 'NR == 1 { print $5 }' <<<"$ready")
    waiting+="${waiting:+, }$owner $(task_label "$first")"
  done < <(team_tasks "$tdir" | awk -F'\t' '$2 != "" && !seen[$2]++ { print $2 }')
  if [[ -n "$waiting" ]]; then
    mkdir -p "$state" 2>/dev/null
    count=$(repeat_count "$key.lead" "$(printf '%s' "$waiting" | cksum | cut -d' ' -f1)")
    if (( count > 6 )); then   # a systemMessage is shown to the user, on an exit-0 path only
      jq -n --arg m "Idle gate: lead went idle with ready tasks nobody is working ($waiting)." '{systemMessage: $m}'
      exit 0
    fi
    echo "Idle gate: ready tasks with nobody working: $waiting. SendMessage the owner to start it, or reassign." >&2
    exit 2
  fi
  rm -f "$key.lead"
fi

globs=$(owned_globs "$who") || exit 0
[[ -z "$globs" ]] && exit 0

dirty=$(dirty_files | while IFS= read -r f; do
  shared_path "$f" && continue
  matches_globs "$f" "$globs" && echo "$f"
done)

mkdir -p "$state" 2>/dev/null

if [[ -z "$dirty" ]]; then
  rm -f "$key"
  # A clean tree is not enough while the teammate has tasks it could be working on.
  ready=""; [[ -n "$tdir" ]] && ready=$(ready_tasks "$tdir" "$who")
  if [[ -z "$ready" ]]; then
    rm -f "$key.tasks"
    exit 0
  fi
  open=$(awk -F'\t' '{ print $1 }' <<<"$ready" | sort -n | paste -sd' ' -)
  subjects=$(awk -F'\t' '{ gsub(/\|/, "/", $5); s = s (NR > 1 ? "; " : "") $5 } END { print s }' <<<"$ready")
  # The same open tasks at the same commit are the same stall: a new commit is progress.
  head=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)
  count=$(repeat_count "$key.tasks" "$(printf '%s %s' "$open" "$head" | cksum | cut -d' ' -f1)")
  if (( count > 6 )); then   # a systemMessage is shown to the user, on an exit-0 path only
    jq -n --arg m "Idle gate: $who stopped after repeated reminders with tasks ready ($subjects)." '{systemMessage: $m}'
    exit 0
  fi
  going=$(awk -F'\t' '$3 == "in_progress" { gsub(/\|/, "/", $5); s = s (s == "" ? "" : "; ") $5 } END { print s }' <<<"$ready")
  pending=$(awk -F'\t' '$3 == "pending" { gsub(/\|/, "/", $5); s = s (s == "" ? "" : "; ") $5 } END { print s }' <<<"$ready")
  [[ -n "$going" ]] && echo "Idle gate: you have $going in progress. Continue it now; if it is done, run its check and TaskUpdate it completed." >&2
  [[ -n "$pending" ]] && echo "Idle gate: you still have tasks ready: $pending. Claim it (TaskUpdate in_progress) and start it now, red tests first. Never stop after a report. If you must wait for an answer, unassign it (TaskUpdate owner \"\") and SendMessage lead naming what you need; the lead gives it back with the answer." >&2
  exit 2
fi

files=$(echo $dirty)
sig=$(printf '%s' "$files" | cksum | cut -d' ' -f1)
prev_sig="" count=0
[[ -f "$key" ]] && read -r prev_sig count < "$key"
if [[ "$prev_sig" == "$sig" ]]; then count=$((count + 1)); else count=1; fi
echo "$sig $count" > "$key"

if (( count > 2 )); then
  escalate "$who" "$files" "$sig"
  jq -n --arg m "Idle gate: $who stopped after two reminders with uncommitted changes in files it owns ($files). Logged as ESCALATED in questions.md for the lead." \
    '{systemMessage: $m}'
  exit 0
fi

echo "Idle gate: uncommitted changes in files you own: $files." >&2
echo "If you wrote them: run typecheck and your tests, commit them (stage by path), then report to the lead." >&2
echo "If you didn't write one of them, don't commit it: tell the lead which file and who may have written it." >&2
if (( count == 2 )); then
  echo "If you can't fix this, SendMessage the lead now with this exact list: $files" >&2
fi
exit 2
