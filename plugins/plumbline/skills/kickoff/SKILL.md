---
name: kickoff
description: Start a new product phase - create its docs folder from templates and mark it current.
disable-model-invocation: true
---
Arguments: <area> <phase-id>   e.g. vet phase-03

1. If docs/product/<area>/vision.md or docs/product/<area>/design-principles.md
   is missing, copy it from the templates/area/ folder next to this SKILL.md and
   replace <Area> with the area name. Never overwrite existing files.
2. Create docs/product/<area>/phases/<phase-id>/ and copy every file from
   templates/phase/ into it. In the copies, replace <phase> with the two-digit
   phase number (phase-03 -> 03).
3. Create contracts/ and prototypes/ inside the phase folder, each with a
   .gitkeep file.
4. Write the phase folder path (relative to the repo root, no trailing slash) as
   the only line of .claude/current-phase.
5. Create and switch to a branch named phase-<nn>-<short-name> from the default
   branch. Ask me for the short name if I didn't give one.
6. Commit the new files and report the folder path. The first documents to
   write are spec.md (product engineer) and ux.md (UX engineer).
