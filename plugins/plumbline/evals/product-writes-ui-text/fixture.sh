#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# Spec and criteria are written; ux.md is still the empty template.
phase_template ux.md
git add -A
git commit -qm "Reset ux.md to the template"
