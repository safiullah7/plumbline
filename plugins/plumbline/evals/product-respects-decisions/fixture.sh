#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
# Phase 01 recorded a decision in decisions.md (and only there). Phase 02 has
# just been kicked off and is current.
cat > "$A/decisions.md" <<'EOF'
# Clinic decisions

Owner: product engineer (product), lead engineer (architecture). One row per
decision that later phases must respect, including options that were rejected,
so nobody reopens them by accident. Read before writing a spec or a dev plan.

| Date | Phase | Kind | Decision | Options rejected | Why |
| --- | --- | --- | --- | --- | --- |
| 2026-10-01 | phase-01 | product | All times are stored and shown in the clinic's local time zone. | Per-user time zones; storing and showing UTC | Staff work on site; per-user zones caused booking mistakes in the old system and doubled support load |
EOF
P=docs/product/clinic/phases/phase-02
mkdir -p "$P"
sed 's/<phase>/02/g' "$FIXTURE_TEMPLATES/phase/spec.md" > "$P/spec.md"
sed 's/<phase>/02/g' "$FIXTURE_TEMPLATES/phase/questions.md" > "$P/questions.md"
echo "$P" > .claude/current-phase
git add -A
git commit -qm "Kick off phase 02"
