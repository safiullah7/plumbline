#!/usr/bin/env bash
# Writes the briefs for each engineer in the dev plan's Team table, in two layers so
# an engineer reads only what its current task needs:
#   briefs/<teammate>.md          the core: what it owns, its surface with that
#                                 surface's checks from docs/product/project.md (and
#                                 the ac-check line for the whole workstream), its
#                                 ordered task list (one line per task: label, IDs,
#                                 title, rating, its file), the contracts it consumes,
#                                 the spec's data and permissions, and a pointer to
#                                 spec.md's business rules.
#   briefs/<teammate>/<label>.md  one task: its whole block (files, failing test, e2e
#                                 test, change, done-when), only the AC rows it cites,
#                                 the attack plan's fixtures line and the rows for the
#                                 SEC IDs it cites (when there are any), the spec's
#                                 business rules that cite its AC or use-case IDs
#                                 (plus a pointer to the rest), the screens
#                                 its criteria's use cases cite with each screen's
#                                 description from ux.md (none for a [chore]), the
#                                 contracts its block mentions, and its tests-only
#                                 ac-check line. A task with no label written gets T<n>.
# briefs/<teammate>/ is cleared before it is written again. A task file over 20 KB
# prints a warning on stderr. Engineers read the core once and a task's file as they
# start it, instead of every phase doc, which is most of a build's reading. The lead
# runs this when it marks the plan READY and again whenever the plan changes. Prints
# each core brief's path; exit 1 when the plan's task labels are wrong (see tasks-lib.sh).
source "$(dirname "${0//\\//}")/lib.sh"
source "$(dirname "${0//\\//}")/tasks-lib.sh"
dir=$(phase_dir) || { echo "make-briefs: no active phase (.claude/current-phase is missing)." >&2; exit 1; }
plan="$dir/dev-plan.md" acs_md="$dir/acceptance-criteria.md" ux="$dir/ux.md"
[[ -f "$plan" ]] || { echo "make-briefs: $plan is missing." >&2; exit 1; }
rel=$(phase_rel)
US=$'\037'
recs=$(tasks_parse "$plan") || { echo "make-briefs: fix the task labels in $plan and run it again." >&2; exit 1; }
mkdir -p "$dir/briefs"

# Raw Markdown table lines (header, separator, rows) under "## <heading>"; with a
# third argument, ### and deeper headings stay inside the section (as in security_rows).
section_table() { # file heading [deep]
  [[ -f "$1" ]] || return 0
  awk -v h="$2" -v deep="${3:-}" '{ sub(/\r$/, "") } /^#+ / { if (deep == "" || $0 !~ /^###/) sec = (index($0, "## " h) == 1); next } sec && /^\|/' "$1"
}
# Keep a table's header and separator, plus the rows matching an ERE.
filter_rows() { # ERE
  awk -v re="$1" 'NR <= 2 || $0 ~ re'
}
alt() { paste -sd'|' -; }
# Every engineer needs the spec's permissions, whatever its tasks; the business
# rules stay in spec.md (the core points there).
rules=$(section_body "$dir/spec.md" "Business rules")
perms=$(section_body "$dir/spec.md" "Data and permissions")

# The screens for a task's AC rows: sets $screens (the inventory rows whose use cases
# those criteria cite) and $screen_text (each listed screen's description, ### <name>
# under ## Screens in ux.md; the whole section only when ux.md has no inventory
# table at all). A task with no criteria (a [chore]) and one whose use cases have
# no screen (an API task) get none.
screens_for() { # the task's AC rows
  screens="" screen_text=""
  grep -qE '^\|[[:space:]]*AC-' <<<"$1" || return 0
  local ucs names whole=0
  ucs=$(grep -oE 'UC-[0-9]+-[0-9]+' <<<"$1" | sort -u)
  screens=$(section_table "$ux" "Screen inventory")
  if [[ -n "$ucs" ]] && head -n1 <<<"$screens" | grep -qi 'use cases'; then
    screens=$(filter_rows "$(alt <<<"$ucs")" <<<"$screens")
  fi
  [[ -z "$screens" ]] && whole=1
  if [[ -f "$ux" ]]; then
    names=$(awk -F'|' 'NR > 2 { n = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", n); if (n != "") print n }' <<<"$screens" | paste -sd'|' -)
    screen_text=$(awk -v names="$names" -v whole="$whole" '{ sub(/\r$/, "") }
      BEGIN { n = split(tolower(names), a, "|"); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
      /^## / { in_s = ($0 ~ /^## Screens[[:space:]]*$/); show = 0; next }
      in_s && /^### / { t = $0; sub(/^### +/, "", t); sub(/[[:space:]]+$/, "", t); show = (whole == 1 || (tolower(t) in want)) }
      in_s && show' "$ux")
  fi
}

# The rows of the engineer's contracts table whose contract name or path the task's
# block mentions; nothing when none do.
task_contracts() { # the engineer's contracts table, the task block
  [[ -n "$1" ]] || return 0
  BLK="$2" awk -F'|' 'BEGIN { blk = tolower(ENVIRON["BLK"]) }
    NR <= 2 { head = head $0 "\n"; next }
    { for (c = 2; c <= 3; c++) { v = tolower($c); gsub(/^[[:space:]`]+|[[:space:]`]+$/, "", v); if (v != "" && index(blk, v)) { rows = rows $0 "\n"; break } } }
    END { if (rows != "") printf "%s%s", head, rows }' <<<"$1"
}

while IFS=$'\t' read -r name _; do
  [[ -n "$name" ]] || continue
  mine=$(awk -F"$US" -v n="$name" '$2 == n' <<<"$recs")
  # Every AC and SEC ID the engineer's task blocks cite, for the workstream's ac-check line.
  all_ids=$(awk -F"$US" '{ print $10 }' <<<"$mine" | tr '\036' '\n')
  all_acs=$(grep -oE 'AC-[0-9]+-[0-9]+' <<<"$all_ids" | sort -u)
  all_secs=$(grep -oE 'SEC-[0-9]+-[0-9]+' <<<"$all_ids" | sort -u)
  contracts=$(section_table "$plan" Contracts)
  if [[ -n "$contracts" ]] && head -n1 <<<"$contracts" | grep -qi 'consumers'; then
    contracts=$(filter_rows "(^|[^[:alnum:]_-])($name|all)([^[:alnum:]_-]|$)" <<<"$contracts")
  fi

  # The workstream's surface: Team column 4, absent in a v0.3-style 3-column plan.
  # With a profile row for it, the row's check commands and the ac-check line.
  surface=$(md_table "$plan" Team | awk -F'\t' -v w="$name" '$1 == w { print $4; exit }' | tr -d '`[:space:]')
  checks="" has_row=0
  if [[ -n "$surface" ]] && row=$(surface_row "$surface"); then
    has_row=1
    cell() { awk -F'\t' -v c="$1" '{ v = $c; gsub(/`/, "", v); print (v == "" ? "(none)" : v) }' <<<"$row"; }
    checks="Typecheck: $(cell 5)
Lint: $(cell 6)
AC tests: $(cell 7)"
    # The workstream-wide command names the engineer's SEC IDs too, so its attack tests run with its AC tests.
    [[ -n "$all_acs$all_secs" ]] && checks="$checks
Once, when all your tasks are done (full run; per task, use the command in its file): bash \"<scripts>/ac-check.sh\" \"$(printf '%s\n%s\n' "$all_acs" "$all_secs" | sed '/^$/d' | alt)\" --surface $surface
(<scripts> is the \"Plumbline scripts\" folder in your context; briefs are committed, so they name no machine path.)"
  fi

  # One file per task, in a folder cleared first so a renamed or removed task leaves nothing behind.
  rm -rf "${dir:?}/briefs/$name"
  [[ -n "$mine" ]] && mkdir -p "$dir/briefs/$name"
  list=""
  while IFS="$US" read -r n owner label ids subject rating blocked done title block; do
    [[ -n "$n" ]] || continue
    tblock=$(tr '\036' '\n' <<<"$block")
    acs=$(grep -oE 'AC-[0-9]+-[0-9]+' <<<"$tblock" | sort -u)
    secs=$(grep -oE 'SEC-[0-9]+-[0-9]+' <<<"$tblock" | sort -u)
    ac_rows=""
    if [[ -n "$acs" && -f "$acs_md" ]]; then
      ac_rows=$(tr -d '\r' < "$acs_md" | grep -E '^\|' | filter_rows "^[|][[:space:]]*($(alt <<<"$acs"))[[:space:]]*[|]")
    fi
    attacks=""
    if [[ -n "$secs" ]]; then
      fixtures=$(awk '{ sub(/\r$/, "") } /^#+ / { if ($0 !~ /^###/) sec = (index($0, "## Attack plan") == 1); next } sec && /^Attack fixtures:/' "$plan")
      arows=$(section_table "$plan" "Attack plan" deep | filter_rows "^[|][[:space:]]*($(alt <<<"$secs"))[[:space:]]*[|]")
      attacks=$(printf '%s\n%s' "$fixtures" "$arows" | sed '/^$/d')
    fi
    screens_for "$ac_rows"
    # The business rules that cite one of the task's AC IDs or its use cases' IDs.
    cites=$( { echo "$acs"; grep -oE 'UC-[0-9]+-[0-9]+' <<<"$ac_rows"; } | sed '/^$/d' | sort -u | alt)
    task_rules=""
    [[ -n "$cites" && -n "$rules" ]] && task_rules=$(RE="($cites)([^0-9]|\$)" awk 'BEGIN { re = ENVIRON["RE"] }
      /^\|/ { t++; if (t <= 2) { head = head $0 "\n"; next } }
      $0 ~ re { if (/^\|/ && head != "") { printf "%s", head; head = "" } print }' <<<"$rules")
    tcontracts=$(task_contracts "$contracts" "$tblock")
    file="$dir/briefs/$name/$label.md"
    {
      echo "# Task $label: ${title:-$subject}, $name, $(basename "$dir")"
      echo
      echo "Generated by make-briefs.sh from the phase docs; don't edit it, change the docs and regenerate."
      echo "This is the one task. Your core brief ($rel/briefs/$name.md) has what you own and the contracts you use."
      echo
      echo "## Task"
      echo "$tblock"
      echo
      echo "## Acceptance criteria for this task"
      echo "${ac_rows:-(none cited)}"
      if [[ -n "$attacks" ]]; then echo; echo "## Attacks to withstand"; echo "$attacks"; fi
      if [[ -n "$screens" ]]; then echo; echo "## Screens"; echo "$screens"; fi
      if [[ -n "$screen_text" ]]; then echo; echo "## Screen descriptions (ux.md)"; echo "$screen_text"; fi
      if [[ -n "$tcontracts" ]]; then echo; echo "## Contracts you use"; echo "$tcontracts"; fi
      echo; echo "## Rules"
      [[ -n "$task_rules" ]] && echo "$task_rules"
      echo "All rules: spec.md, '## Business rules' (read it if a case isn't covered above)."
      if (( has_row )) && [[ -n "$acs$secs" ]]; then
        echo; echo "## Check"
        echo "bash \"<scripts>/ac-check.sh\" --tests-only \"$(printf '%s\n%s\n' "$acs" "$secs" | sed '/^$/d' | alt)\" --surface $surface"
        echo "(Tests only; typecheck and lint run once per workstream. <scripts> is the \"Plumbline scripts\" folder in your context.)"
      fi
    } > "$file"
    size=$(wc -c < "$file")
    (( size > 20480 )) && echo "make-briefs: warning: $file is $((size / 1024)) KB (over 20 KB); split the task or shorten its block." >&2
    list="$list${list:+$'\n'}- $label [${ids:-chore}] ${title:-$subject}${rating:+ ($rating)}${blocked:+, after ${blocked//,/, }}: $rel/briefs/$name/$label.md"
  done <<<"$mine"

  out="$dir/briefs/$name.md"
  {
    echo "# Brief: $name, $(basename "$dir")"
    echo
    echo "Generated by make-briefs.sh from the phase docs; don't edit it, change the docs and regenerate."
    echo "Read this core once. Start each task from its own file below; open the full docs only when they aren't enough."
    echo
    echo "## You own"
    echo "$(owned_globs "$name")"
    if [[ -n "$surface" ]]; then
      echo; echo "## Your surface"
      echo "Surface: $surface"
      [[ -n "$checks" ]] && echo "$checks"
    fi
    echo
    echo "## Your tasks (in this order)"
    echo "${list:-(none listed in dev-plan.md)}"
    if [[ -n "$contracts" ]]; then echo; echo "## Contracts you use"; echo "$contracts"; fi
    if [[ -n "$perms" ]]; then echo; echo "## Data and permissions (spec.md)"; echo "$perms"; fi
    if [[ -n "$rules" ]]; then echo; echo "## Business rules"; echo "In $rel/spec.md, section \"Business rules\". Open it when a task file points there."; fi
    echo
    echo "## Full docs"
    echo "$rel/spec.md, $rel/acceptance-criteria.md, $rel/ux.md, $rel/dev-plan.md, $rel/contracts/"
  } > "$out"
  echo "$out"
done < <(md_table "$plan" Team)
