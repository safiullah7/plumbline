#!/usr/bin/env bash
# Evidence for choosing the next feature, from every feature of the active module
# (new <nn>-<slug>/ folders and legacy phases/<phase>/ folders alike, in number
# order): what shipped with known problems (open medium/low bugs and design findings,
# WONTFIX bugs), what was deliberately left out (Non-Goals), success metrics
# that weren't met, and recorded blockers. Prints raw text, at most 80 lines,
# for /plumbline:phase-next. Read-only.
source "$(dirname "${0//\\//}")/lib.sh"
module=$(module_dir) || { echo "No active phase: .claude/current-phase is missing."; exit 1; }
rel_module=${module#"$PROJECT_DIR"/}
closed='^(FIXED|RESOLVED|CLOSED|VERIFIED|DONE)$'

# Feature folders of both layouts, one "<number> <path>" line each, by number; a
# legacy phases/ folder without a number (v0.3 listed every one) goes after them.
features() {
  local d n
  for d in "$module"/[0-9][0-9]*-*/ "$module"/phases/*/; do
    [[ -d "$d" ]] || continue   # an unmatched glob stays as written
    d=${d%/}; n=${d##*/}; n=${n#phase-}
    if [[ "$n" =~ ^([0-9]+) ]]; then echo "$((10#${BASH_REMATCH[1]})) $d"; else echo "999999999999 $d"; fi
  done | LC_ALL=C sort -s -k1,1n | cut -d' ' -f2-
}

{
  echo "Evidence for the next feature in $rel_module. Also read $rel_module/vision.md and $rel_module/decisions.md."
  while IFS= read -r p; do
    bugs=$(md_table "$p/qa-report.md" Bugs 2>/dev/null | awk -F'\t' -v c="$closed" '
      $1 != "" { s = toupper($4); v = tolower($3) }
      $1 != "" && (s == "WONTFIX" || (s !~ c && (v == "medium" || v == "low"))) { printf "- %s (%s, %s): %s\n", $1, v, tolower($4), $5 }')
    findings=$( {
      md_table "$p/signoff.md" "Product findings" 2>/dev/null | awk -F'\t' -v c="$closed" '$1 != "" && toupper($4) !~ c { printf "- product #%s (%s): %s\n", $1, tolower($4), $3 }'
      md_table "$p/signoff.md" "Design findings" 2>/dev/null | awk -F'\t' -v c="$closed" '$1 != "" && toupper($5) !~ c { printf "- design #%s (%s, %s): %s\n", $1, tolower($4), tolower($5), $3 }'
    } )
    metrics=$(md_table "$p/signoff.md" "Success metrics results" 2>/dev/null | awk -F'\t' '$1 != "" && tolower($4) != "yes" { printf "- %s: target %s, result %s (met: %s)\n", $1, $2, $3, ($4 == "" ? "pending" : $4) }')
    nongoals=$(section_body "$p/spec.md" "Non-Goals")
    [[ -n "$nongoals" ]] || nongoals=$(section_body "$p/spec.md" "Out of scope")
    blockers=$(grep -iE 'blocker' "$p/progress.md" 2>/dev/null | head -n 3)
    [[ -n "$bugs$findings$metrics$nongoals$blockers" ]] || continue
    echo
    echo "## $(basename "$p")"
    [[ -n "$metrics" ]] && { echo "Success metrics not met:"; echo "$metrics"; }
    [[ -n "$bugs" ]] && { echo "Bugs shipped or waived:"; echo "$bugs"; }
    [[ -n "$findings" ]] && { echo "Open findings:"; echo "$findings"; }
    [[ -n "$nongoals" ]] && { echo "Left out on purpose (Non-Goals):"; echo "$nongoals"; }
    [[ -n "$blockers" ]] && { echo "Blockers noted in progress.md:"; echo "$blockers"; }
  done < <(features)
} | head -n 80
