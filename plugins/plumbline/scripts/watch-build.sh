#!/usr/bin/env bash
# The main session's watchdog during a build. Usage:
#   watch-build.sh [--sleep <seconds>] [--stall-minutes <n>]
# Sleeps (default 0), then prints one line per teammate of this project's team from
# the shared task list and git: its ready tasks, its task in progress, the minutes
# since its last activity and its uncommitted owned files. Activity is the newest of:
# its last commit touching the globs it owns (the dev plan's Ownership table), the
# newest file change under those globs, and the newest change to its task files.
# A teammate with a ready or in-progress task and no activity for --stall-minutes
# (default 5) also gets "STALLED: <name> (<task subject>)". When every engineer task
# is completed but the lead's chores aren't, it prints "LEAD: <open chores>" and
# "STALLED: lead (<first open chore>)" after the same minutes with no lead activity
# (its task files' changes, commits touching docs/product/**). The last line is
# "DONE" only when every task, the lead's chores included, is completed, and
# "NO-TASKS" (not DONE) when the team has no task list yet: setup isn't finished.
# Notifications aren't a reliable wake-up, so the build skill loops this and sends
# "Continue: <task>" to each stalled teammate. The team is found like status.sh does
# (team configs whose cwd is this project, or PLUMBLINE_TEAM). Read-only; exit 0.
source "$(dirname "${0//\\//}")/lib.sh"
sleep_s=0 stall_min=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sleep) sleep_s="${2:-0}"; shift 2 ;;
    --stall-minutes) stall_min="${2:-5}"; shift 2 ;;
    *) echo "Usage: watch-build.sh [--sleep <seconds>] [--stall-minutes <n>]" >&2; exit 0 ;;
  esac
done
[[ "$sleep_s" =~ ^[0-9]+$ ]] || sleep_s=0
[[ "$stall_min" =~ ^[0-9]+$ ]] || stall_min=5
(( sleep_s > 0 )) && sleep "$sleep_s"

team=$(team_for_project) && tdir=$(team_dir_for "$team") \
  || { echo "watch-build: no team task list found for this project (set PLUMBLINE_TEAM to name the team)."; exit 0; }
cd "$PROJECT_DIR" || exit 0
tasks=$(team_tasks "$tdir")
[[ -n "$tasks" ]] || { echo "watch-build: team $team has no tasks yet."; echo "NO-TASKS"; exit 0; }

# File modification time in epoch seconds: GNU stat first, then BSD/macOS.
if stat -c %Y . >/dev/null 2>&1; then mtimes() { xargs -0 -r stat -c %Y; }; else mtimes() { xargs -0 -r stat -f %m; }; fi
now=$(date +%s)
dirty=$(dirty_files)
repo_files=$( { git ls-files; git ls-files -o --exclude-standard; } 2>/dev/null | tr -d '\r')

# Done: every task, the lead's chores included, is completed. Engineers done: every
# task that isn't the lead's is completed (and there is at least one); nobody else is
# stalled then, and the lead's own chores may be all that is left.
finished="" engdone="" chores=""
awk -F'\t' '{ n++; if ($3 != "completed") open++ } END { exit !(n > 0 && open == 0) }' <<<"$tasks" && finished=1
awk -F'\t' '$2 != "lead" && $2 != "team-lead" { n++; if ($3 != "completed") open++ } END { exit !(n > 0 && open == 0) }' <<<"$tasks" && engdone=1
chores=$(awk -F'\t' '($2 == "lead" || $2 == "team-lead") && $3 != "completed" { print $5 }' <<<"$tasks")

# Members: the team config's, plus every task owner (a config may list only the lead).
names=$( { jqr '.members[]?.name' "$(norm_path "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")/teams/$team/config.json" 2>/dev/null
           awk -F'\t' '$2 != "" { print $2 }' <<<"$tasks"; } | grep -vx 'team-lead' | awk 'NF && !seen[$0]++')

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  ready=$(ready_tasks "$tdir" "$name")
  working=$(awk -F'\t' '$3 == "in_progress" { print $5; exit }' <<<"$ready")
  next=$(awk -F'\t' '$3 == "pending" { print $5; exit }' <<<"$ready")
  last=0
  # Task files this teammate owns: every touch of a task updates its file.
  while IFS= read -r id; do
    [[ -f "$tdir/$id.json" ]] || continue
    m=$(printf '%s\0' "$tdir/$id.json" | mtimes)
    (( m > last )) && last=$m
  done < <(awk -F'\t' -v o="$name" '$2 == o { print $1 }' <<<"$tasks")
  globs=$(owned_globs "$name" 2>/dev/null) || globs=""
  nd=0
  if [[ -n "$globs" ]]; then
    specs=(); set -f; for g in $globs; do specs+=(":(glob)$g"); done; set +f
    c=$(git log -1 --format=%ct -- "${specs[@]}" 2>/dev/null)
    [[ "$c" =~ ^[0-9]+$ ]] && (( c > last )) && last=$c
    m=$(while IFS= read -r f; do matches_globs "$f" "$globs" && printf '%s\0' "$f"; done <<<"$repo_files" \
      | mtimes | sort -n | tail -n 1)
    [[ "$m" =~ ^[0-9]+$ ]] && (( m > last )) && last=$m
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      shared_path "$f" && continue
      matches_globs "$f" "$globs" && nd=$((nd + 1))
    done <<<"$dirty"
  fi
  mins=$(( (now - last) / 60 )); (( last == 0 )) && mins=-1
  queued=$(awk -F'\t' '$3 == "pending" { s = s (s == "" ? "" : "; ") $5 } END { print s }' <<<"$ready")
  echo "$name: ready: ${queued:-none} · in progress: ${working:-none} · idle $( ((mins < 0)) && echo unknown || echo "${mins}m") · uncommitted $nd"
  # The lead is judged below, once the engineers are done.
  if [[ "$name" != lead && -z "$engdone" && -n "$ready" ]] && (( mins < 0 || mins >= stall_min )); then
    echo "STALLED: $name (${working:-$next})"
  fi
done <<<"$names"

# The lead's chores left over once every engineer task is completed: the lead's
# activity is its task files and the commits that touch docs/product/**.
if [[ -n "$engdone" && -n "$chores" ]]; then
  echo "LEAD: $(paste -sd';' - <<<"$chores" | sed 's/;/; /g')"
  last=0
  while IFS= read -r id; do
    [[ -f "$tdir/$id.json" ]] || continue
    m=$(printf '%s\0' "$tdir/$id.json" | mtimes)
    (( m > last )) && last=$m
  done < <(awk -F'\t' '$2 == "lead" || $2 == "team-lead" { print $1 }' <<<"$tasks")
  c=$(git log -1 --format=%ct -- ":(glob)docs/product/**" 2>/dev/null)
  [[ "$c" =~ ^[0-9]+$ ]] && (( c > last )) && last=$c
  mins=$(( (now - last) / 60 )); (( last == 0 )) && mins=-1
  (( mins < 0 || mins >= stall_min )) && echo "STALLED: lead ($(head -n1 <<<"$chores"))"
fi

[[ -n "$finished" ]] && echo "DONE"
exit 0
