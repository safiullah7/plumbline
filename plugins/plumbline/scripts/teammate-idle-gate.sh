#!/usr/bin/env bash
# TeammateIdle: a teammate can't go idle with uncommitted changes in files it owns.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

build_active || exit 0
require_jq
who=$(jqr '.teammate_name // empty' <<<"$input")
globs=$(owned_globs "$who") || exit 0
[[ -z "$globs" ]] && exit 0

cd "$PROJECT_DIR" || exit 0
set -f   # treat globs as patterns, never expand them against the disk
dirty=$(git status --porcelain --untracked-files=all | tr -d '\r' | awk '{print $NF}' | while read -r f; do
  for g in $globs; do [[ "$f" == $g ]] && { echo "$f"; break; }; done
done)

if [[ -n "$dirty" ]]; then
  echo "Idle gate: uncommitted changes in files you own: $(echo $dirty)." >&2
  echo "Run typecheck and your tests, commit them (stage by path), then report to the lead." >&2
  exit 2
fi
exit 0
