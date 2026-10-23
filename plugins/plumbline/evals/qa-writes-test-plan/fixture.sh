#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# The test plan is still the template.
phase_template test-plan.md
git add -A
git commit -qm "Add test plan template"
