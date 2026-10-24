#!/usr/bin/env bash
# TeammateIdle: a teammate can't go idle with uncommitted changes in files it owns.
# It pushes back at most twice for the same set of files, then lets the teammate
# stop, so a teammate that can't fix it never loops forever. A hook can't message
# the lead, so giving up logs an ESCALATED row in the phase's questions.md, which
# /plumbline:signoff won't pass.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

# Append one ESCALATED row for the lead to questions.md, once per set of files.
# Creates the file with the template header if it's missing, numbers the row
# after the highest existing one, and keeps the file's line endings.
escalate() {
  local who="$1" files="$2" sig="$3" dir q n nl=$'\n'
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
  printf '| %s | hooks | lead | %s stopped after two reminders with uncommitted changes in files it owns: %s. Commit them or decide who should. (idle-gate %s) | | ESCALATED |%s' \
    "$n" "$who" "$files" "$sig" "$nl" >> "$q"
}

build_active || exit 0
require_jq
who=$(jqr '.teammate_name // empty' <<<"$input")
session=$(jqr '.session_id // empty' <<<"$input")
globs=$(owned_globs "$who") || exit 0
[[ -z "$globs" ]] && exit 0

dirty=$(dirty_files | while IFS= read -r f; do
  shared_path "$f" && continue
  matches_globs "$f" "$globs" && echo "$f"
done)

state="$(norm_path "${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}")/plumbline-idle"
mkdir -p "$state" 2>/dev/null
key="$state/${session:-none}-${who//[^A-Za-z0-9_-]/_}"

if [[ -z "$dirty" ]]; then
  rm -f "$key"
  exit 0
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
