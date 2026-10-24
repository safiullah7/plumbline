#!/usr/bin/env bash
# Helpers for the v0.4b fixtures: a project profile and feature docs, both built
# from the plugin's own templates and scripts, so a case always sees the plugin
# version under test. Source it from a fixture:
#   source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"
set -e
FIXTURE_TEMPLATES="${FIXTURE_TEMPLATES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/kickoff/templates" && pwd)}"
FIXTURE_SCRIPTS="$(cd "$FIXTURE_TEMPLATES/../../../scripts" && pwd)"

# project_profile <multi-tenant: yes|no> <sensitive data> <surface rows> [generic commands]
# Writes docs/product/project.md from templates/project.md: the placeholder rows
# become the given rows (one line each, 7 cells), and the "## Generic commands"
# placeholder becomes the given section body (omitted when empty).
project_profile() {
  local tenant="$1" sensitive="$2" rows="$3" generic="${4:-}"
  mkdir -p docs/product
  ROWS="$rows" awk '
    /^## Generic commands/ { exit }
    /^\| <surface> \|/ { if (!done) { print ENVIRON["ROWS"]; done = 1 } next }
    { print }' "$FIXTURE_TEMPLATES/project.md" \
    | sed -e 's/^Confirmed by: <user> on <date>\./Confirmed by: eval on 2026-10-01./' \
          -e "s/^Multi-tenant: no\$/Multi-tenant: $tenant/" \
          -e "s/^Sensitive data: none\$/Sensitive data: $sensitive/" > docs/product/project.md
  if [[ -n "$generic" ]]; then
    printf '\n## Generic commands\n%s\n' "$generic" >> docs/product/project.md
  fi
}

# new_feature <module> <slug> <profile> <surfaces> [--no-ux]
# Runs the plugin's kickoff.sh in the current repo (a new module when its folder
# doesn't exist yet) and sets FEATURE to the printed feature folder.
new_feature() {
  local module="$1" slug="$2" profile="$3" surfaces="$4" ux="${5:---ux}" newmod=""
  [[ -d "docs/product/$module" ]] || newmod="--new-module"
  FEATURE=$(bash "$FIXTURE_SCRIPTS/kickoff.sh" "$module" "$slug" --profile "$profile" "$ux" $newmod --surfaces "$surfaces" | tail -n 1)
}
