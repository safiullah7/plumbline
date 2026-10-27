#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# The dev plan is still the template.
phase_template dev-plan.md
git add -A
git commit -qm "Add dev plan template"
