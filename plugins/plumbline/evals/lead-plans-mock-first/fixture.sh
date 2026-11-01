#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# The dev plan is still the template, and neither the rooms API nor the UI is
# built yet (the fixture's demo handlers are removed): the UI will call the API.
phase_template dev-plan.md
git rm -q apps/api/rooms/routes.js apps/api/rooms/store.js
git add -A
git commit -qm "Add dev plan template; the rooms API is not built yet"
