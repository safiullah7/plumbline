#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/flutter.sh"
cat > "$F/test-plan.md" <<'EOT'
# Feature 01 test plan

Owner: QA engineer. Written from spec.md and acceptance-criteria.md before the
build starts, never from the code.

## Traceability
| AC ID | Test cases | Type | Status |
| --- | --- | --- | --- |
| AC-01-001 | TC-01-001 save a note online | flow | planned |
| AC-01-002 | TC-01-002 2001 characters disables Save | widget | planned |
| AC-01-003 | TC-01-003 airplane mode keeps the note across a restart | flow | planned |
| AC-01-004 | TC-01-004 the badge clears when the network returns | flow | planned |
| AC-01-005 | TC-01-005 a rejected note shows Retry | flow | planned |
| AC-01-006 | TC-01-006 camera permission denied | flow | planned |

## Evidence
- screenshots (mobile-ui): AC-01-001 AC-01-003 AC-01-005, from the emulator at
  390x844 and 430x932, kept in qa/shots/<screen>-<width>.png.
- flow-tests (mobile-ui): AC-01-001 to AC-01-006, run with
  `flutter test integration_test`, test names starting with the AC ID.
- checklist (mobile-ui): touch targets, screen-reader labels, text scaling and
  contrast on the Job screen, kept in qa/a11y-checklist.tsv.
EOT
git add -A
git commit -qm "Feature 01 built; test plan ready for QA"
