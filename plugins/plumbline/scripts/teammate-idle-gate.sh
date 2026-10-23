#!/usr/bin/env bash
# TeammateIdle: a teammate can't go idle with uncommitted changes in files it owns.
# It pushes back at most twice for the same set of files, then lets the teammate
# stop and tells you, so a teammate that can't fix it never loops forever.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

build_active || exit 0
require_jq
who=$(jqr '.teammate_name // empty' <<<"$input")
session=$(jqr '.session_id // empty' <<<"$input")
globs=$(owned_globs "$who") || exit 0
[[ -z "$globs" ]] && exit 0

cd "$PROJECT_DIR" || exit 0
set -f   # treat globs as patterns, never expand them against the disk
dirty=$(git status --porcelain --untracked-files=all | tr -d '\r' | awk '{print $NF}' | while read -r f; do
  for g in $globs; do [[ "$f" == $g ]] && { echo "$f"; break; }; done
done)
set +f

state="$(norm_path "${TMPDIR:-/tmp}")/plumbline-idle"
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
  jq -n --arg m "Idle gate: $who still has uncommitted changes in files it owns ($files) after two reminders. Letting it stop; ask the lead to sort it out." \
    '{systemMessage: $m}'
  exit 0
fi

echo "Idle gate: uncommitted changes in files you own: $files." >&2
echo "If you wrote them: run typecheck and your tests, commit them (stage by path), then report to the lead." >&2
echo "If you didn't write one of them, don't commit it: tell the lead which file and who may have written it." >&2
exit 2
