---
name: kickoff
description: Start a new product phase - create its docs folder from templates and mark it current.
disable-model-invocation: true
---
Arguments: <area> <phase-id>   e.g. vet phase-03

1. For each file in the templates/area/ folder next to this SKILL.md (vision.md,
   design-principles.md, decisions.md): if docs/product/<area>/ doesn't have it,
   copy it there, replacing <Area> with the area name and <area> with the folder
   name. Never overwrite existing files.
2. Create docs/product/<area>/phases/<phase-id>/ and copy every file from
   templates/phase/ into it. In the copies, replace <phase> with the two-digit
   phase number (phase-03 -> 03).
3. Create contracts/, prototypes/ and briefs/ inside the phase folder, each with
   a .gitkeep file.
4. Write the phase folder path (relative to the repo root, no trailing slash) as
   the only line of .claude/current-phase. Claude Code asks permission for files
   in .claude/; if the write is refused, tell me the exact line to put there.
5. Create and switch to a branch named phase-<nn>-<short-name> from the default
   branch. Ask me for the short name if I didn't give one.
6. Commit the new files and report the folder path. Next steps: /plumbline:discover
   to interview me and draft spec.md (product engineer), then ux.md (UX engineer).
