---
name: kickoff
description: Start a new feature (or a legacy phase) - create its docs folder from templates and mark it current.
disable-model-invocation: true
argument-hint: "<module> <feature-slug> [--profile standard|full] [--ux|--no-ux] [--new-module] [--surfaces s1,s2] | <area> phase-NN"
---
Arguments, in either form:
- Module form: `<module> <feature-slug> [--profile standard|full] [--ux|--no-ux]
  [--new-module] [--surfaces s1,s2]`, e.g. `rooms room-schedules --profile standard`.
  Defaults: full, with UX (with --surfaces: UX only if a surface is a web-ui,
  mobile-ui or desktop-ui; --ux or --no-ux wins).
- Legacy form: `<area> <phase-id> [short-name]`, e.g. `vet phase-03`.

<plugin> is the folder two levels above this SKILL.md.

1. Module form with docs/product/project.md and no `--surfaces`: ask which of
   the profile's surfaces the feature touches (propose the ones whose Paths
   fit), and add `--surfaces` with the answer. With a shell, if
   `git rev-parse --show-toplevel` isn't the folder this session started in,
   stop and say to start Claude Code in the repo root. Then run
   `bash <plugin>/scripts/kickoff.sh <arguments, without the short name>`.
   It creates the docs (never overwriting existing ones), writes
   .claude/current-phase, prints `added <path>` for each module or area doc it
   adds, and prints the feature folder as its last line. Exit 1: show its
   message and stop. Exit 2: the module already exists; ask whether to add the
   feature to it (run again without --new-module) or stop.
2. Create and switch to a branch from the default branch. Legacy form:
   phase-<nn>-<short-name>; ask me for the short name if I didn't give one.
   Module form: feature/<nn>-<feature-slug>, with <nn> from the printed folder.
3. Commit the new files by path (the added docs, the feature folder and
   .claude/current-phase) and report the folder path. Next steps:
   /plumbline:discover to interview me and draft spec.md (product engineer),
   then ux.md (UX engineer); module form without UX: discover only.

**Hand fallback** (no shell, or the command is refused): create exactly the
files the script would, from the templates/ folder next to this SKILL.md. Never
overwrite an existing file. The display name of a folder name is its dashes as
spaces with the first letter capitalised (vet-records -> Vet records).
- Legacy form:
  1. Copy each file of templates/area/ (vision.md, design-principles.md,
     decisions.md) that docs/product/<area>/ lacks, replacing <Area> with the
     area's display name and <area> with the folder name.
  2. Create docs/product/<area>/phases/<phase-id>/ with a copy of every file in
     templates/phase/, replacing <phase> with the number (phase-03 -> 03).
  3. Create contracts/, prototypes/ and briefs/ in it, each with an empty
     .gitkeep. No .plumbline file.
- Module form:
  1. <nn>: the highest number among docs/product/*/<nn>-*/ and
     docs/product/*/phases/phase-<nn>/ folders, plus 1, two digits (01 if none).
     The folder is docs/product/<module>/<nn>-<feature-slug>/, or
     docs/product/<module>/phases/phase-<nn>/ if the module has a phases/
     folder. Stop if the module already has this slug (a <nn>-<slug>/ folder,
     or a phases/*/.plumbline with `slug=<slug>`), or, with --new-module, if
     docs/product/<module>/ exists. With --surfaces, check every name now: it
     must be one of web-ui, mobile-ui, desktop-ui, api, service, cli, library,
     data, ai, infra, or one of them plus `-<name>` (web-ui-shop is a web-ui).
     Any other name: stop, create nothing, and list the ten.
     UX: with --surfaces and neither --ux nor --no-ux, UX is yes only if some
     surface is a web-ui, mobile-ui or desktop-ui, else no. An explicit flag
     wins. Without --surfaces, UX is yes.
  2. Copy the module docs it lacks from templates/module/: vision.md,
     decisions.md, changes.md, and design-principles.md unless no UX.
  3. Copy every file of templates/phase/ into the folder; for the standard
     profile, then copy templates/standard/ over them. Without UX, skip ux.md
     and delete the `- [ ] Design verification` line from signoff.md. In every
     copy replace `Phase <phase>` with `Feature <nn>`, then <phase> with <nn>,
     <Module> with the module's display name and <module> with the module.
  4. Surface overlays, after step 3, one pass per kind in the order given
     (two surfaces of one kind apply it once): mobile-ui uses
     templates/surface/mobile/, api uses surface/api/, ai uses surface/ai/, cli
     uses surface/cli/; other kinds have none. In an overlay folder a file
     `<doc>.append.md` goes at the end of the feature's `<doc>.md`, after a
     blank line, only if that doc exists (no ux.md without UX: skip
     ux.append.md). Any other file is copied to the same relative path
     (contracts/README.md), never over an existing file. Make the same
     replacements as in step 3 in what you add.
  5. Create contracts/ and briefs/ (and prototypes/ with UX), each with an
     empty .gitkeep.
  6. Write <folder>/.plumbline, one per line: `module=<module>`, `number=<nn>`,
     `slug=<feature-slug>`, `profile=<standard|full>`, `surfaces=<s1,s2>` (only if given),
     `ux=<yes|no>`, `created=<YYYY-MM-DD>`.
- Both: write the folder path (relative to the repo root, no trailing slash)
  as the only line of .claude/current-phase. Claude Code asks permission for
  files in .claude/; if the write is refused, tell me the exact line to put
  there. Without a shell, skip the branch and commit, say so, and report the
  folder path and the next steps.
