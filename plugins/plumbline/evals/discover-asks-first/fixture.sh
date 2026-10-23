#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# Phase 02 has just been kicked off and is the current phase.
P=docs/product/clinic/phases/phase-02
mkdir -p "$P"
sed 's/<phase>/02/g' "$FIXTURE_TEMPLATES/phase/spec.md" > "$P/spec.md"
sed 's/<phase>/02/g' "$FIXTURE_TEMPLATES/phase/questions.md" > "$P/questions.md"
echo "$P" > .claude/current-phase
git add -A
git commit -qm "Kick off phase 02"
