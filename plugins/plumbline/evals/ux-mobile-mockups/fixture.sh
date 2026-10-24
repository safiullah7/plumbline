#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/flutter.sh"
# kickoff appended the mobile overlay (device sizes, iOS and Android, the
# accessibility checklist) to ux.md. Put the plain template back so the graders
# only see what the UX engineer writes.
sed -e 's/Phase <phase>/Feature 01/g' -e 's/<phase>/01/g' "$FIXTURE_TEMPLATES/phase/ux.md" > "$F/ux.md"
git add -A
git commit -qm "Reset ux.md to the plain template"
