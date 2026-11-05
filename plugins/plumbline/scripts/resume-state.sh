#!/usr/bin/env bash
# Where an interrupted feature stands and what comes next, for /plumbline:resume.
# Read-only: it runs no tests and changes nothing. One line per fact, then the
# stage to resume at:
#   Phase: <folder> · size <full|standard> · security <level> (required: <parts>)
#   Branch: <current> · feature branch <name> (on it | exists | missing)
#   Plan: <status> · <n> tasks (<owner> <n>, ...)        or: unreadable (<why>)
#   Task list: none | <open> of <total> open (<owner> <n>, ...)
#   Signoff: integration review <yes|no> · QA verdict <...> · product verification <yes|no> · PR <link|none> · merged <yes|no>
#   Security: independent pass "<text>" · findings: #<n> <severity> <status>, ... · deferred <n>   (only above none)
#   Bugs: <id> <severity> <status>, ... | none open
#   Questions: for the user: <#>, ... · for agents: <#> (<to>), ... · escalated: <#>, ...
#   Uncommitted: none | <n> files (by owner: <name> <n>, ...; unowned <n>)
#   Progress: <the first line of progress.md that isn't blank or a heading: the newest note>
#   Next: spec | plan | build | attack | verify | signoff | merge | done
# Next is the first stage not finished: spec (no AC IDs in acceptance-criteria.md),
# plan (dev plan not READY), build (Integration review unticked in signoff.md),
# attack (the independent pass is required and isn't "complete (round <n>)", or a
# finding is fixed but not verified, or a critical or high one is open or deferred
# and not accepted; a medium or low finding marked deferred never sends it back,
# since it is follow-up work), verify (QA verdict not PASS, an open high or critical bug, or Product
# verification unticked), signoff (no PR link), merge (PR open, not merged), done.
# Exit 0 = printed; 1 = no active phase (.claude/current-phase is missing).
source "$(dirname "${0//\\//}")/lib.sh"
dir=$(phase_dir) || { echo "resume-state: no active phase: .claude/current-phase is missing."; exit 1; }
[[ -d "$dir" ]] || { echo "resume-state: the active phase folder $(phase_rel) doesn't exist."; exit 1; }
cd "$PROJECT_DIR" || exit 1
rel=$(phase_rel)
US=$'\037'
join() { paste -sd, - | sed 's/,/, /g'; }

# --- the feature ---
size=$(feature_meta profile)
lvl=$(security_level)
req=$(security_required "$lvl")
line="Phase: $rel · size ${size:-full} · security $lvl"
[[ "$lvl" != none ]] && line+=" (required: $req)"
echo "$line"

num=$(feature_meta number) slug=$(feature_meta slug)
cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -n "$num" && -n "$slug" ]]; then
  fb="feature/$num-$slug"
  if [[ "$cur" == "$fb" ]]; then where="on it"
  elif git rev-parse --verify --quiet "refs/heads/$fb" >/dev/null; then where="exists"
  else where="missing"; fi
  echo "Branch: ${cur:-unknown} · feature branch $fb ($where)"
else
  echo "Branch: ${cur:-unknown} · feature branch unknown (no number= and slug= in .plumbline)"
fi

# --- the plan and its tasks ---
pstatus=$(plan_status)
if [[ -z "$pstatus" ]]; then
  echo "Plan: none"
else
  errf=$(mktemp)
  tasks=$(bash "$(dirname "${0//\\//}")/plan-tasks.sh" --dir "$dir" 2>"$errf"); prc=$?
  err=$(head -n1 "$errf"); rm -f "$errf"
  if (( prc == 0 )) && [[ -n "$tasks" ]]; then
    per=$(cut -f1 <<<"$tasks" | awk '{ n[$0]++; if (!($0 in o)) { o[$0] = ++k; name[k] = $0 } } END { for (i = 1; i <= k; i++) print name[i] " " n[name[i]] }' | join)
    echo "Plan: $pstatus · $(grep -c . <<<"$tasks") tasks ($per)"
  else
    echo "Plan: $pstatus · tasks unreadable (${err:-plan-tasks.sh found none})"
  fi
fi

if team=$(team_for_project) && tdir=$(team_dir_for "$team") && tl=$(team_tasks "$tdir") && [[ -n "$tl" ]]; then
  open=$(awk -F'\t' '$3 != "completed"' <<<"$tl")
  per=$(awk -F'\t' '{ o = ($2 == "" ? "unassigned" : $2); n[o]++; if (!(o in s)) { s[o] = ++k; name[k] = o } } END { for (i = 1; i <= k; i++) print name[i] " " n[name[i]] }' <<<"$open" | join)
  echo "Task list: $(grep -c . <<<"$open") of $(grep -c . <<<"$tl") open${per:+ ($per)}"
else
  echo "Task list: none"
fi

# --- signoff.md boxes ---
box() { # name prefix -> yes|no
  awk -v p="$1" '{ sub(/\r$/, "") } index($0, "- [") == 1 && index(substr($0, 7), p) == 1 { print (tolower(substr($0, 4, 1)) == "x" ? "yes" : "no"); f = 1; exit } END { if (!f) print "no" }' "$dir/signoff.md" 2>/dev/null || echo no
}
integ=$(box "Integration review")
prodv=$(box "Product verification")
merged=$(box "Merged")
pr=$(awk '{ sub(/\r$/, "") } index($0, "- [") == 1 && index(substr($0, 7), "Feature PR opened:") == 1 { sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$dir/signoff.md" 2>/dev/null)
verdict=$(grep -m1 -iE '^Verdict:' "$dir/qa-report.md" 2>/dev/null | tr -d '\r' | sed -E 's/^[Vv]erdict:[[:space:]]*//')
echo "Signoff: integration review $integ · QA verdict ${verdict:-none} · product verification $prodv · PR ${pr:-none} · merged $merged"

# --- security ---
attack_left=""
if [[ "$lvl" != none ]]; then
  st=$(security_independent_state)
  f=$(security_rows findings 2>/dev/null | awk -F"$US" '$1 == "row" { n = $2; sub(/^#/, "", n); printf "#%s %s %s\n", n, tolower($3), tolower($5) }')
  ndef=$(grep -c ' deferred$' <<<"$f")
  echo "Security: independent pass \"${st:-none}\" · findings: $( [[ -n "$f" ]] && join <<<"$f" || echo none) · deferred $ndef"
  if [[ " $req " == *" independent "* ]]; then
    [[ "$st" =~ ^[Cc]omplete[[:space:]]*\(round[[:space:]]+[0-9]+\)$ ]] || attack_left=1
  fi
  while IFS="$US" read -r kind n sev txt fst _; do
    [[ "$kind" == row ]] || continue
    n="${n#\#}"
    sev=$(tr '[:upper:]' '[:lower:]' <<<"$sev"); fst=$(tr '[:upper:]' '[:lower:]' <<<"$fst")
    [[ "$fst" == fixed ]] && attack_left=1
    if [[ "$fst" != verified && ( "$sev" == critical || "$sev" == high ) ]]; then
      security_accepted "#$n $sev $txt" 1 || attack_left=1
    fi
  done < <(security_rows findings 2>/dev/null)
fi

# --- bugs and questions ---
bugs=$(md_table "$dir/qa-report.md" Bugs 2>/dev/null | awk -F'\t' '$1 != "" && toupper($4) !~ /^(VERIFIED|WONTFIX|CLOSED)$/ { print $1 " " tolower($3) " " tolower($4) }')
echo "Bugs: $( [[ -n "$bugs" ]] && join <<<"$bugs" || echo none open)"
openhigh=$(md_table "$dir/qa-report.md" Bugs 2>/dev/null | awk -F'\t' '$1 != "" && toupper($4) !~ /^(FIXED|VERIFIED|WONTFIX|CLOSED)$/ && tolower($3) ~ /^(high|critical)$/' | grep -c .)

q=$(md_table "$dir/questions.md" 2>/dev/null)
quser=$(awk -F'\t' 'toupper($6) == "OPEN" && tolower($3) ~ /user/ { print $1 }' <<<"$q" | join)
qagent=$(awk -F'\t' 'toupper($6) == "OPEN" && tolower($3) !~ /user/ { print $1 " (" $3 ")" }' <<<"$q" | join)
qesc=$(awk -F'\t' 'toupper($6) == "ESCALATED" { print $1 }' <<<"$q" | join)
echo "Questions: for the user: ${quser:-none} · for agents: ${qagent:-none} · escalated: ${qesc:-none}"

# --- uncommitted work, by owner ---
dirty=$(dirty_files)
if [[ -z "$dirty" ]]; then
  echo "Uncommitted: none"
else
  own=$(md_table "$dir/dev-plan.md" Ownership 2>/dev/null)
  byowner=$(while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      shared_path "$f" && { echo shared; continue; }
      who=""
      while IFS=$'\t' read -r name globs _; do
        [[ -n "$name" ]] && matches_globs "$f" "$globs" && { who="$name"; break; }
      done <<<"$own"
      echo "${who:-unowned}"
    done <<<"$dirty" | awk '{ n[$0]++; if (!($0 in s)) { s[$0] = ++k; name[k] = $0 } } END { for (i = 1; i <= k; i++) print name[i] " " n[name[i]] }' | join)
  echo "Uncommitted: $(grep -c . <<<"$dirty") files (by owner: $byowner)"
fi

top=$(awk '{ sub(/\r$/, "") } /[^[:space:]]/ && !/^#/ { print substr($0, 1, 200); exit }' "$dir/progress.md" 2>/dev/null)
echo "Progress: ${top:-no entry}"

# --- the stage to resume at ---
ac=$(md_table "$dir/acceptance-criteria.md" 2>/dev/null | awk -F'\t' '$1 ~ /^AC-[0-9]+-[0-9]+$/' | grep -c .)
if (( ac == 0 )); then next=spec
elif ! grep -qiE '^READY$' <<<"$pstatus"; then next=plan
elif [[ "$integ" != yes ]]; then next=build
elif [[ -n "$attack_left" ]]; then next=attack
elif [[ "$(tr '[:lower:]' '[:upper:]' <<<"$verdict")" != PASS || "$openhigh" -gt 0 || "$prodv" != yes ]]; then next=verify
elif [[ -z "$pr" ]]; then next=signoff
elif [[ "$merged" != yes ]]; then next=merge
else next=done
fi
echo "Next: $next"
