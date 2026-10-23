#!/usr/bin/env bash
# Writes acceptance-criteria.json beside acceptance-criteria.md for the active
# phase (or the phase folder given): [{id, useCase, priority, status}], where
# status is the AC's result in qa-report.md's Traceability results, or
# "untested". Scripts and agents read the JSON instead of re-reading Markdown.
# Prints the file's path.
source "$(dirname "${0//\\//}")/lib.sh"
require_jq
dir="${1:-$(phase_dir)}"
if [[ -z "$dir" || ! -f "$dir/acceptance-criteria.md" ]]; then
  echo "ac-json: no acceptance-criteria.md in ${dir:-the active phase}" >&2
  exit 1
fi

results=$(md_table "$dir/qa-report.md" "Traceability results" 2>/dev/null)
md_table "$dir/acceptance-criteria.md" | awk -F'\t' '$1 ~ /^AC-[0-9]+-[0-9]+$/' \
  | jq -R -s --arg r "$results" '
      ($r | split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] // "")})
          | from_entries) as $res
      | split("\n") | map(select(length > 0) | split("\t"))
      | map({id: .[0], useCase: (.[1] // ""), priority: (.[5] // ""),
             status: (($res[.[0]] // "") | if . == "" then "untested" else ascii_downcase end)})' \
  | tr -d '\r' > "$dir/acceptance-criteria.json"
echo "$dir/acceptance-criteria.json"
