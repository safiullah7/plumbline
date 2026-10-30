#!/usr/bin/env bash
# Writes briefs/<teammate>.md for each engineer in the dev plan's Team table: its
# Ownership row, its surface (the Team table's Surface column, when there is one)
# with that surface's checks from docs/product/project.md, its tasks (each task's
# whole block: the files, the failing test, the e2e test, the change, the
# done-when), only the AC rows those tasks cite, the attack plan's fixtures line
# and the rows for the SEC IDs those tasks cite (when there are any), the screens
# for those use cases with each screen's description from ux.md, and the contracts
# it consumes, ending with links to the full docs. Engineers read their brief first
# instead of every phase doc, which is most of a build's reading. The lead runs this when it marks the plan READY and
# again whenever the plan changes. Prints each brief's path.
source "$(dirname "${0//\\//}")/lib.sh"
dir=$(phase_dir) || { echo "make-briefs: no active phase (.claude/current-phase is missing)." >&2; exit 1; }
plan="$dir/dev-plan.md" acs_md="$dir/acceptance-criteria.md" ux="$dir/ux.md"
[[ -f "$plan" ]] || { echo "make-briefs: $plan is missing." >&2; exit 1; }
rel=$(phase_rel)
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
# Every engineer needs the spec's rules and permissions, whatever its tasks.
rules=$(section_body "$dir/spec.md" "Business rules")
perms=$(section_body "$dir/spec.md" "Data and permissions")

while IFS=$'\t' read -r name _; do
  [[ -n "$name" ]] || continue
  tasks=$(awk -v n="$name" '{ sub(/\r$/, "") }
    /^## / { t = ($0 ~ /^## Tasks/); me = 0; next }
    t && /^### / { me = ($0 == "### " n); next }
    t && me && (/^[-*] / || /^[[:space:]]+[^[:space:]]/)' "$plan")
  acs=$(grep -oE 'AC-[0-9]+-[0-9]+' <<<"$tasks" | sort -u)
  ac_rows=""
  if [[ -n "$acs" && -f "$acs_md" ]]; then
    ac_rows=$(tr -d '\r' < "$acs_md" | grep -E '^\|' | filter_rows "^[|][[:space:]]*($(alt <<<"$acs"))[[:space:]]*[|]")
  fi
  secs=$(grep -oE 'SEC-[0-9]+-[0-9]+' <<<"$tasks" | sort -u)
  attacks=""
  if [[ -n "$secs" ]]; then
    fixtures=$(awk '{ sub(/\r$/, "") } /^#+ / { if ($0 !~ /^###/) sec = (index($0, "## Attack plan") == 1); next } sec && /^Attack fixtures:/' "$plan")
    rows=$(section_table "$plan" "Attack plan" deep | filter_rows "^[|][[:space:]]*($(alt <<<"$secs"))[[:space:]]*[|]")
    attacks=$(printf '%s\n%s' "$fixtures" "$rows" | sed '/^$/d')
  fi
  ucs=$(grep -oE 'UC-[0-9]+-[0-9]+' <<<"$ac_rows" | sort -u)
  screens=$(section_table "$ux" "Screen inventory")
  if [[ -n "$ucs" ]] && head -n1 <<<"$screens" | grep -qi 'use cases'; then
    screens=$(filter_rows "$(alt <<<"$ucs")" <<<"$screens")
  fi
  # Each listed screen's description (### <name> under ## Screens); the whole
  # section only when ux.md has no inventory table at all. An engineer whose use
  # cases have no screen (an API workstream) gets none.
  screen_text="" whole=0
  [[ -z "$screens" ]] && whole=1
  if [[ -f "$ux" ]]; then
    names=$(awk -F'|' 'NR > 2 { n = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", n); if (n != "") print n }' <<<"$screens" | paste -sd'|' -)
    screen_text=$(awk -v names="$names" -v whole="$whole" '{ sub(/\r$/, "") }
      BEGIN { n = split(tolower(names), a, "|"); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
      /^## / { in_s = ($0 ~ /^## Screens[[:space:]]*$/); show = 0; next }
      in_s && /^### / { t = $0; sub(/^### +/, "", t); sub(/[[:space:]]+$/, "", t); show = (whole == 1 || (tolower(t) in want)) }
      in_s && show' "$ux")
  fi
  contracts=$(section_table "$plan" Contracts)
  if [[ -n "$contracts" ]] && head -n1 <<<"$contracts" | grep -qi 'consumers'; then
    contracts=$(filter_rows "(^|[^[:alnum:]_-])($name|all)([^[:alnum:]_-]|$)" <<<"$contracts")
  fi

  # The workstream's surface: Team column 4, absent in a v0.3-style 3-column plan.
  # With a profile row for it, the row's check commands and the ac-check line.
  surface=$(md_table "$plan" Team | awk -F'\t' -v w="$name" '$1 == w { print $4; exit }' | tr -d '`[:space:]')
  checks=""
  if [[ -n "$surface" ]] && row=$(surface_row "$surface"); then
    cell() { awk -F'\t' -v c="$1" '{ v = $c; gsub(/`/, "", v); print (v == "" ? "(none)" : v) }' <<<"$row"; }
    checks="Typecheck: $(cell 5)
Lint: $(cell 6)
AC tests: $(cell 7)"
    # The command names the engineer's SEC IDs too, so its attack tests run with its AC tests.
    [[ -n "$acs$secs" ]] && checks="$checks
Before you report a task done: bash \"<scripts>/ac-check.sh\" \"$(printf '%s\n%s\n' "$acs" "$secs" | sed '/^$/d' | alt)\" --surface $surface
(<scripts> is the \"Plumbline scripts\" folder in your context; briefs are committed, so they name no machine path.)"
  fi

  out="$dir/briefs/$name.md"
  {
    echo "# Brief: $name, $(basename "$dir")"
    echo
    echo "Generated by make-briefs.sh from the phase docs; don't edit it, change the docs and regenerate."
    echo "Read this first. Open the full docs only when it isn't enough."
    echo
    echo "## You own"
    echo "$(owned_globs "$name")"
    if [[ -n "$surface" ]]; then
      echo; echo "## Your surface"
      echo "Surface: $surface"
      [[ -n "$checks" ]] && echo "$checks"
    fi
    echo
    echo "## Your tasks"
    echo "${tasks:-(none listed in dev-plan.md)}"
    echo
    echo "## Acceptance criteria for your tasks"
    echo "${ac_rows:-(none cited)}"
    if [[ -n "$attacks" ]]; then echo; echo "## Attacks to withstand"; echo "$attacks"; fi
    if [[ -n "$rules" ]]; then echo; echo "## Business rules (spec.md)"; echo "$rules"; fi
    if [[ -n "$perms" ]]; then echo; echo "## Data and permissions (spec.md)"; echo "$perms"; fi
    if [[ -n "$screens" ]]; then echo; echo "## Screens"; echo "$screens"; fi
    if [[ -n "$screen_text" ]]; then echo; echo "## Screen descriptions (ux.md)"; echo "$screen_text"; fi
    if [[ -n "$contracts" ]]; then echo; echo "## Contracts you use"; echo "$contracts"; fi
    echo
    echo "## Full docs"
    echo "$rel/spec.md, $rel/acceptance-criteria.md, $rel/ux.md, $rel/dev-plan.md, $rel/contracts/"
  } > "$out"
  echo "$out"
done < <(md_table "$plan" Team)
