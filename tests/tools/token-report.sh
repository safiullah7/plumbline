#!/usr/bin/env bash
# Token use per role for one Claude Code session that ran an agent team: the
# lead's transcript plus each teammate's and subagent's (<session>/subagents/).
# It reads Claude Code's local transcripts, an unofficial format, so it's for our
# own before/after measurements only. Usage:
#   bash tests/tools/token-report.sh <session.jsonl>
#   bash tests/tools/token-report.sh --latest <project dir>   # e.g. 'D:\Repos\plumbline-e2e'
set -u
command -v jq >/dev/null 2>&1 || { echo "jq isn't installed or isn't on PATH." >&2; exit 1; }

if [[ "${1:-}" == --latest ]]; then
  slug=$(printf '%s' "${2:?project dir}" | sed -e 's#[:\\/]#-#g')
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$slug"
  lead=$(ls -t "$base"/*.jsonl 2>/dev/null | head -n1)
else
  lead="${1:?session transcript (.jsonl)}"
fi
command -v cygpath >/dev/null 2>&1 && lead=$(cygpath -u "$lead")
[[ -f "$lead" ]] || { echo "No transcript found: ${lead:-none}" >&2; exit 1; }

# One line per assistant message (deduplicated by id): model, input, cache write,
# cache read, output.
usage() {
  tr -d '\r' < "$1" | jq -r 'select(.type == "assistant" and .message.usage != null)
    | [.message.id, .message.model, (.message.usage.input_tokens // 0),
       (.message.usage.cache_creation_input_tokens // 0),
       (.message.usage.cache_read_input_tokens // 0), (.message.usage.output_tokens // 0)] | @tsv' \
  | awk -F'\t' '!seen[$1]++ { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }'
}
row() { # role file
  usage "$2" | awk -F'\t' -v role="$1" '
    { m[$1] = 1; i += $2; w += $3; r += $4; o += $5; n++ }
    END {
      models = ""; for (k in m) models = models (models ? "," : "") k
      printf "| %s | %s | %d | %d | %d | %d | %d | %d |\n", role, models, n, i, w, r, o, i + w + r + o
    }'
}

echo "Session: $lead"
echo
echo "| Role | Model | Messages | Input | Cache write | Cache read | Output | Total |"
echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
row lead "$lead"
dir="${lead%.jsonl}/subagents"
for t in "$dir"/agent-*.jsonl; do
  [[ -f "$t" ]] || continue
  meta="${t%.jsonl}.meta.json" name=""
  [[ -f "$meta" ]] && name=$(tr -d '\r' < "$meta" | jq -r '(.name // empty) + (if .agentType and .agentType != .name then " (" + .agentType + ")" else "" end)')
  [[ -n "$name" ]] || name=$(basename "$t" .jsonl)
  row "$name" "$t"
done
