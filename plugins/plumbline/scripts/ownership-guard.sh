#!/usr/bin/env bash
# PreToolUse (Edit/Write/MultiEdit/NotebookEdit/Bash). Three locks apply to any
# agent (teammate or plain subagent, whether or not the plan is READY); the main
# session is always allowed:
#   - .plumbline is feature metadata written by kickoff.sh, never by an agent;
#   - docs/product/project.md lists the commands the gates run (the TaskCompleted
#     hook and ac-check.sh run its cells without a prompt), so an agent can't
#     change it; reading it stays allowed;
#   - a waiver line ("Evidence waived:", "Accessibility waived:") can only come
#     from the user, through the lead's main session. The guard judges the file
#     the edit would produce, so a waiver can't be pieced together from fragments,
#     and waiver lines the file already holds may stay.
# An agent's Bash command gets a best-effort check against accidental writes (a
# waiver phrase, or a redirect or file command aimed at .plumbline or project.md);
# it is not a sandbox, and Bash never goes through the ownership check.
# During Build, a teammate may also only edit files it owns in the dev plan's
# Ownership table. Exit 2 = block + feedback.
source "$(dirname "${0//\\//}")/lib.sh"
input=$(cat); debug_log "$input"

if ! command -v jq >/dev/null 2>&1; then
  # The locks need jq: only a running build insists on it, and never for Bash,
  # so the session can still run the command that installs jq.
  grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"Bash"' <<<"$input" && exit 0
  build_active && require_jq
  exit 0
fi
file=$(jqr '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
agent_id=$(jqr '.agent_id // empty' <<<"$input")
agent_type=$(jqr '.agent_type // empty' <<<"$input")
tool=$(jqr '.tool_name // empty' <<<"$input")
[[ -z "$agent_id" ]] && exit 0                    # the lead's own session

meta_msg="Plumbline: .plumbline is feature metadata written by kickoff.sh; ask the lead or the user to change it."
profile_msg="Plumbline: docs/product/project.md lists the commands the gates run; only the user changes it (through the main session). Tell the lead what should change."
waiver_msg="Only the user can approve a waiver. Tell the lead which evidence is missing and why; the build skill will ask the user."

if [[ "$tool" == Bash ]]; then
  cmd=$(jqr '.tool_input.command // empty' <<<"$input")
  cmd="${cmd//$'\\\n'/ }"                         # join continued lines
  if grep -qiE '(evidence|accessibility)[^[:alnum:]]*waived[[:space:]]*:' <<<"$cmd"; then
    echo "$waiver_msg To search for one, grep for \"waived\" without the colon." >&2
    exit 2
  fi
  # One simple command per line; a write is a redirect, tee, an in-place sed or
  # perl, or a file command with the file after it. Reading it stays allowed.
  # project.md is matched by name alone (a cd into docs/product still hits it).
  writes_to() { # ERE for the file's name
    tr '|;&' '\n\n\n' <<<"$cmd" | grep -iE "$1" | grep -qiE \
      -e ">.*$1" \
      -e "(^|[^[:alnum:]_.-])(tee|mv|cp|rm|truncate|dd)[[:space:]].*$1" \
      -e '(^|[^[:alnum:]_.-])(sed|perl)[[:space:]](.*[[:space:]])?(-[[:alnum:]]*i|--in-place)'
  }
  if writes_to '\.plumbline'; then
    echo "$meta_msg" >&2
    exit 2
  fi
  if writes_to '(^|[^[:alnum:]_.-])project\.md($|[^[:alnum:]_.-])'; then
    echo "$profile_msg" >&2
    exit 2
  fi
  exit 0
fi

# NTFS and default APFS ignore case, and Win32 drops trailing dots and spaces and
# reads "name:stream" as the file itself, so all of those spell .plumbline too.
base="${file//\\//}"; base="${base##*/}"; base="${base%%:*}"
while [[ "$base" == *[.\ ] ]]; do base="${base%?}"; done
if [[ "$(printf '%s' "$base" | tr 'A-Z' 'a-z')" == .plumbline ]]; then
  echo "$meta_msg" >&2
  exit 2
fi

# The profile gets the same treatment, by its path from the project folder, in any
# case and with the same Windows spellings (trailing dots and spaces, a stream).
if [[ -n "$file" ]]; then
  prof=$(norm_path "$file"); prof_root=$(norm_path "$PROJECT_DIR")
  [[ "$prof" == /* || "$prof" == [A-Za-z]:/* ]] || prof="$prof_root/$prof"
  prof=$(printf '%s' "$prof" | tr 'A-Z' 'a-z'); prof_root=$(printf '%s' "$prof_root" | tr 'A-Z' 'a-z')
  prof="${prof#"$prof_root"/}"; prof="${prof%%:*}"
  while [[ "$prof" == *[.\ ] ]]; do prof="${prof%?}"; done
  if [[ "$prof" == docs/product/project.md ]]; then
    echo "$profile_msg" >&2
    exit 2
  fi
fi

# The text the tool would leave in the file: Write's content, or the current file
# with each edit applied in order (an edit whose old text isn't there adds its new
# text, so nothing slips past a stale read). The file goes to jq on stdin, never
# as an argument, to stay under Windows' command-line limit.
target=""; [[ -n "$file" ]] && target=$(norm_path "$file")
new_text=$({ printf '%s\n' "$input"
  if [[ -f "$target" ]]; then jq -Rs . < "$target"; else echo '""'; fi
} | jqr -s '.[0].tool_input as $t | (.[1] // "") as $cur
  | if ($t.new_source | type) == "string" then $t.new_source
    elif ($t.content | type) == "string" then $t.content
    else reduce ((if ($t.edits | type) == "array" then $t.edits[] else $t end) | select(type == "object")) as $e ($cur;
      (if ($e.old_string | type) == "string" then $e.old_string else "" end) as $o
      | (if ($e.new_string | type) == "string" then $e.new_string else "" end) as $n
      | if $o == "" then $n elif index($o) != null then split($o) | join($n) else . + "\n" + $n end)
    end')
# A waiver line starts with Evidence or Accessibility (after optional marks such as
# "- ", "> " or "**"), then "waived:"; a mention mid-sentence is not one. Block only
# lines the file doesn't hold yet; a notebook's new cell counts as all new.
waiver_lines() {
  grep -iE '^[^[:alnum:]]*(evidence|accessibility)[^[:alnum:]]*waived[[:space:]]*:' | tr -d '\r' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | LC_ALL=C sort -u
}
old_w=""
[[ -f "$target" && "$tool" != NotebookEdit && "$target" != *.ipynb ]] && old_w=$(waiver_lines < "$target")
new_w=$(waiver_lines <<<"$new_text")
if [[ -n "$new_w" ]] && LC_ALL=C comm -13 <(printf '%s\n' "$old_w") <(printf '%s\n' "$new_w") | grep -q .; then
  echo "$waiver_msg" >&2
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
