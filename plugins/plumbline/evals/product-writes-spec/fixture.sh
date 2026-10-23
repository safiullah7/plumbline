#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# Phase 02 has just been kicked off: its spec is still the template.
P=docs/product/clinic/phases/phase-02
mkdir -p "$P"
sed 's/<phase>/02/g' "$FIXTURE_TEMPLATES/phase/spec.md" > "$P/spec.md"
git add -A
git commit -qm "Kick off phase 02"
