#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/modules.sh"
# Feature 01 was just built: code, unit tests, ux.md journeys and criteria exist.
# The functional test record and the QA report are still the templates.
sed -i.bak 's/| Done |$/| In progress |/' docs/product/rooms/vision.md && rm -f docs/product/rooms/vision.md.bak
mkdir -p .claude
echo "docs/product/rooms/01-room-management" > .claude/current-phase
git add -A
git commit -qm "Feature 01 built, ready for QA"
