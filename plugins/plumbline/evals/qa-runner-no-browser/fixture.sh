#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
phase_template qa-report.md
phase_template test-plan.md
git add -A
git commit -qm "Phase 01 build done; QA next"
