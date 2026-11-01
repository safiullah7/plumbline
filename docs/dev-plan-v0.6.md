# Plumbline v0.6: fast builds (no stalls, right-sized features, lean checks)

Status: plan reviewed once against the code (a read-only critique found 8
issues, all folded in: lead-first setup sequencing, a separate idle-gate
state file, the lead's own idle rule, the unblocked-owner wake-up, `[chore]`
checks, self-tests that pin old behaviour, label rules, eval tool limits).

## Context

The first live run of v0.5 (DineFlow staff portal: 90 criteria, 28 attack
rows, 2 engineers) took 6.5+ hours and was still not done. Log analysis
(2026-10-31) showed where the 381 minutes went:

| Slice | Minutes | Share |
| --- | --- | --- |
| Nobody doing anything (stalls) | ~152 | 40% |
| Docs and planning before any code | ~81 | 21% |
| Waiting on the user | ~30 | 8% |
| "Contracts first" with engineers waiting | 13 | 3% |
| At least one engineer building | ~105 | 28% |

Root causes, each with evidence in the logs:
1. **Deadlock.** Engineers reported to `team-lead` (the main session), not to
   `lead`; they ended turns with "starting B4 next" and no tool call; the lead
   waited for reports it never got. The idle gate only checks for uncommitted
   files, so a clean tree may idle with tasks left. The shared task list was
   never used (0 TaskCreated events in that run), so nothing knew what was
   still open.
2. **Scope.** One Full feature with 90 criteria made 275 KB of docs (a 94 KB
   plan, 279 KB of briefs) and 111 minutes before the first line of code.
   Nothing in triage or product caps a feature or splits a request.
3. **Serial team.** 14 tasks on 2 engineers in serial chains; all three
   agents were active together for 6.8 minutes; the portal waited 20 minutes
   for an API task instead of building against a mock (no prompt mentions
   mocks).
4. **Checks per task.** `ac-check` ran typecheck + lint + the suite on every
   task (and the lead re-ran it); real-Clerk Playwright runs took 2–4 min
   each; checks were 35–45% of engineer active time.
5. **Context bloat.** 80–93 KB briefs re-read 14 times each; 8 context
   resets. A brief copies every task block, all its criteria, all business
   rules and all screens; there is no per-task slice.

Already fixed on branch `v0.5.1-plan-review` (8fcf0f2, unmerged): the plan
wasn't shown before the approval question; the lead copied removed roles from
an older feature's plan. v0.6 builds on that branch.

**Goal:** the same 90-criteria request in about 3 hours; a right-sized
~25-criteria feature in 1.5–2 hours; every quality gate kept (spec, criteria,
TDD with unit + e2e, attack tests, review, QA, signoff).

## Facts that shape the design (verified in the code)

- `TeammateIdle` payload carries `teammate_name` and `team_name`; the shared
  task list is on disk at `~/.claude/tasks/<team_name>/<id>.json` with
  `subject`, `owner`, `status` (pending | in_progress | completed),
  `blockedBy[]`. So a hook can know a teammate's open tasks, once tasks exist.
- `teammate-idle-gate.sh` exits before any check when the teammate has no
  Ownership row (the lead), then checks only uncommitted owned files; nudges
  twice (exit 2 + stderr), then escalates (questions.md row + systemMessage).
  State file: `$CLAUDE_PLUGIN_DATA|$TMPDIR/plumbline-idle/<session>-<name>`.
- `task-completed-gate.sh` runs `run_checks` = typecheck, lint, then the AC
  tests (lib.sh:407-427). A set-but-empty `PLUMBLINE_TYPECHECK`/`LINT` skips
  that step repo-wide; there is no per-task "tests only".
- `make-briefs.sh` builds one brief per Team row: all task blocks under
  `### <name>`, the cited criteria rows, attacks, business rules and data
  permissions copied whole, screens (everything when no UC is cited),
  contracts by consumer. `context.sh` injects only a pointer to the brief.
- Prompts: product triage has no criteria cap and no split rule
  (`product-engineer.md:106-169`); the lead's "5-6 tasks per engineer in the
  shared task list" (`lead-engineer.md:~138`) is never enforced; the lead
  reviews per workstream (:148-165) but engineers run full `ac-check` per
  task (`senior-engineer.md` step 4); nothing mentions mocks; the build skill
  has no spawn-prompt text and never names the lead (`build/SKILL.md` 6.4).
- Evals pin formats: Team header, `- [AC-…] title (RATING)` task lines with
  `Red (unit):`/`E2E:`/`Done when:`, `Engineers: 2-4` for a new module,
  `Engineers: 1` for Quick, `Status: DRAFT`, docs-only rows. New lines are
  additive.

## Design

### 1. No stalls (deterministic core + prompts)

**Task list as the source of truth, created by the lead at setup.**
- New `scripts/plan-tasks.sh`: prints one line per task from `dev-plan.md`
  `## Tasks` (`### <owner>` sections, the lead's `[chore]` lines included):
  `owner<TAB>subject<TAB>blocked-by labels<TAB>done-when`. Task lines gain an
  explicit label: `- [AC-02-030 SEC-02-007] B4: Status changes (HIGH)`; the
  label is `^[A-Z]{1,2}[0-9]{1,3}` followed by `:`; a line without one gets a
  plan-global `T<n>`. `Blocked by: B1, L0` lines (new, optional) list labels;
  an unknown or duplicate label is an error (exit 1, the lead fixes the plan).
  Subjects are checked against the task-created gate's rule before printing
  (`\r` stripped; `|` is fine in TSV). The dev-plan template documents the
  label and `Blocked by:`.
- Sequencing (the lead already sets READY and runs `make-briefs.sh`): after
  approval the build skill spawns **the lead first**; the lead sets READY,
  runs `make-briefs.sh`, commits the docs and `contracts/` (this is L0, so
  contracts land before any engineer exists, which keeps the
  `plan-quality` grader happy), runs `plan-tasks.sh` and creates every task
  with TaskCreate (owner and `addBlockedBy` by label → id), then reports
  "ready" to the main session. The skill then spawns the engineers (the team
  task list lives in `~/.claude/tasks/<team_name>/`, which is what the idle
  gate's `team_name` points at because the lead is a teammate; the live run
  verifies this).
- Engineers claim (`TaskUpdate in_progress`) before starting a task and
  complete it when done (the TaskCompleted gate runs its tests).
- `task-completed-gate.sh`, on a pass, also prints a `systemMessage` naming
  the tasks this completion unblocked and their owners ("You unblocked
  eng-portal's F3: SendMessage eng-portal now"), so a blocked engineer is
  woken by the one who unblocked it, deterministically.

**Idle gate v2** (`teammate-idle-gate.sh`):
- The dirty-files check stays first and unchanged. The new check runs in
  the clean-tree branch (before the `rm -f "$key"; exit 0`), with its own
  state file `${key}.tasks` so the two counts never reset each other. It
  reads `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/tasks/<team_name>/*.json`
  (no dir, or jq failure → exit 0, old behaviour). The teammate's **ready
  tasks** = `owner == teammate_name` and (`status == in_progress`, or
  `pending` with every `blockedBy` id completed; a missing id counts as
  completed).
- Engineers: ready tasks → exit 2 with `Idle gate: you still have tasks
  ready: [AC-02-030 …] B4: Status changes. Claim it (TaskUpdate in_progress)
  and start it now, red tests first. Never stop after a report. If you are
  waiting on an answer, set the task back to pending and SendMessage lead
  naming what you need.` Three nudges per signature (sorted open ids), then
  the escalation row (text generalised: `stopped after three reminders with
  tasks ready: <subjects>`) plus `systemMessage`; it keeps refusing up to
  six, then allows (safety valve).
- The lead (`teammate_name` `lead`; the skill assigns that name): no nudge
  for its own chores, but if any engineer has a ready task and nothing of
  theirs is `in_progress`, exit 2 with `Idle gate: ready tasks with nobody
  working: eng-portal F3. SendMessage the owner to start it, or reassign.`
- `status.sh` and `watch-build.sh` have no payload: they find the team by
  matching `teams/*/config.json` `cwd` to the project dir (newest wins), or
  `PLUMBLINE_TEAM`.
- `status.sh`: a `team:` line from the task list when it exists
  (`team: eng-api 2 open (1 ready) · eng-portal 3 open · lead 4 chores`), so
  the main session and the lead can see a stall in one call.

**Watchdog in the main session (the second stall, 2026-10-31 01:00).** The
team stalled again the same way after the first nudge (all three idle
~1h40 after 23:39; a nudge at 01:0x restarted them: B5 red at 01:20). The
main session had `ReadNotifications: No queued notifications` although the
TeammateIdle hook fired hundreds of times, and it had decided "I'm not
polling, new reports will wake me". So notifications are not a reliable
wake-up, and the main session must not wait passively:
- New `scripts/watch-build.sh [--sleep <seconds>]`: sleeps, then prints one
  line per teammate from the task list and git: ready tasks, in-progress
  task, minutes since its last commit or file change under its globs,
  uncommitted owned files; and a `STALLED: <name> (<task>)` line for a
  teammate with a ready or in-progress task and no activity for 10 minutes.
- Build skill 6.4: after spawning, the main session loops `bash
  <scripts>/watch-build.sh --sleep 600` (foreground, 10-minute Bash
  timeout) until the lead reports the build done; for each `STALLED` line it
  sends `Continue: <task>` to that teammate (and wakes the lead when a
  workstream is done but unreviewed). One cheap turn per 10 minutes.
- Idle gate cap (D4): three nudges (exit 2), then an escalation row and a
  `systemMessage`; it keeps refusing idle up to six times per signature,
  then allows it (a safety valve against a confused teammate looping).

**Prompts.**
- `senior-engineer.md`: report to the lead by its teammate name, `lead`
  (never `team-lead`); after a report, claim and start the next ready task
  **in the same turn**; a turn never ends on an announcement ("starting B4
  next"): the next thing is a tool call; idle only when no task is ready, and
  then the report names the blocker. Drop "before you go idle…" wording;
  progress.md lines are written with the task report instead.
- `lead-engineer.md`: at setup (after approval) set READY, run
  `make-briefs.sh`, commit docs and contracts, run `plan-tasks.sh` and create
  every task it prints (owner, blockedBy), then report "ready" to the main
  session; write a label on every task and `Blocked by:` on every dependent
  one; answer
  every report with accept/reject **and** the engineer's next task; when a
  task that others were blocked on completes, message those engineers; a
  quiet teammate with ready tasks is a stall: message it; don't re-run
  `ac-check` per task (once per workstream, at acceptance).
- `build/SKILL.md` 6.4: spawn the lead first (name `lead`) with the setup
  instruction above; when it reports "ready", spawn the engineers from a
  literal template: name, brief path and task folder, surface, `effort`,
  "report to `lead`", "claim and complete tasks in the shared list; keep
  going through your ready tasks without waiting for a verdict". The main
  session never relays reports (if one arrives, forward it to `lead` once
  and say so), and runs the watchdog loop below instead of waiting.

### 2. Right-sized features (scope cap + split)

- `product-engineer.md` triage: a feature is at most **~30 criteria and ~6
  screens**. When the request implies more (a module from scratch, several
  journeys), triage prints a `Split:` line: `Split: 1 of 3 — 02 sign-in and
  order queue (this) · 03 order detail and status changes · 04 refresh,
  switching, personal-data pass`, each slice a shippable step. The build skill
  shows it, asks once (Full already asks), builds slice 1, and product adds
  the other slices as rows to the module's `vision.md` Features table so
  `/plumbline:phase-next` picks them up.
- Product's spec rules: criteria ≤ 30 per feature (P0 and P1 first; P2 beyond
  the cap moves to the next slice with a `Deferred to <nn>` note);
  `ux.md` describes only this slice's screens.
- Lead: ≤ 12 tasks per plan, task blocks ≤ ~1.5 KB; attack plan stays
  catalogue-driven (usually 4–12 rows).

### 3. A parallel team

- `lead-engineer.md`: team size by load, not only by seams: a surface with
  more than ~5 tasks gets two engineers with disjoint globs (feature
  subfolders), up to the triage max (4). Dependencies are written as `Blocked
  by:` labels, not prose.
- **Mock-first.** A task that needs another workstream's unfinished output
  (an API the UI calls) is planned against the contract with a mock (MSW, a
  fixture server, a stub module), plus one final "switch to the real API"
  task blocked by the API task. `senior-engineer.md`: never wait on another
  workstream; build against the contract with a mock and say so in the
  report.
- **Contracts during planning, not after approval.** The lead writes
  `contracts/` (and migration files) while planning so the user approves them
  with the plan; L0 is the lead's setup commit (docs + contracts) made before
  any engineer is spawned, so no engineer waits on it; only tasks that touch
  migrations are `Blocked by: L0`.
- Triage keeps `Engineers:` by file areas (max 4; the `engineers-2-4` and
  `one-engineer` graders stay valid); the lead applies the load rule when it
  plans. The `Split:` line is added to both places that print the block
  (`product-engineer.md` and build step 3); `Size: Full` is kept on a split
  request, so `triage-full-new-module` still passes.

### 4. Lean checks

- `ac-check.sh --tests-only`: a new case in its flag loop; it exports the
  two typecheck/lint vars empty before `run_checks` (so it overrides a
  user's explicit `PLUMBLINE_TYPECHECK`; documented). `task-completed-gate.sh`
  runs tests-only by default for tasks with IDs; `[chore]` tasks (no IDs)
  keep typecheck + lint, otherwise they would check nothing;
  `PLUMBLINE_TASK_CHECKS=full` restores the old behaviour everywhere. The
  existing hook and lib self-tests export `PLUMBLINE_TASK_CHECKS=full` at the
  top (they assert the typecheck/lint runs) and new cases cover the default.
  Typecheck and lint run once per workstream at the lead's acceptance
  (`ac-check` full) and the signoff skill runs `ac-check` full per surface
  (today it says only "the full test suite").
- Briefs: the core brief's `ac-check` line lists the workstream's IDs (for
  acceptance); each task file carries its own
  `ac-check.sh --tests-only "<the task's IDs>"` line.
- `senior-engineer.md` TDD: red is proven by the unit test's failing run;
  the e2e test is written in red but **run at green** (one e2e run per task);
  step 4 uses `--tests-only`; the full suite runs at workstream end.
- By-surface conventions: e2e against an external identity provider uses the
  provider's testing mode or test tokens; real sign-in is QA's job.
- Lead: no per-task `ac-check`; one full run per workstream before the
  reviewer.

### 5. Small context

- `make-briefs.sh` per-task slices: `briefs/<eng>.md` becomes the **core**
  (you own, surface and commands, the ordered task list one line per task
  with its label and file, contracts, data and permissions, and a pointer to
  spec.md's business-rules section instead of a copy) and
  `briefs/<eng>/<label>.md` holds one task: the task block, only its
  criteria rows, its attack rows, the screens its criteria's use cases cite
  (none for a `[chore]`), the contracts it consumes, and its tests-only
  `ac-check` line. `briefs/<eng>/` is cleared before regeneration. A task
  file over 20 KB prints a warning. The scripts and lib self-tests that pin
  the old single-file sections (`scripts-selftest.sh` make-briefs cases,
  `lib-selftest.sh` ~:462-490) are updated to the new layout.
- `context.sh`: "Your brief: briefs/<eng>.md; your tasks: briefs/<eng>/;
  read the current task's file when you start it, nothing else".
- `senior-engineer.md`: read the core once and each task file as you start
  it; don't re-read the plan or the spec unless the task file points there.
- Lead: keep the Tasks list in memory; read a plan section with the file
  tool only when needed (not the whole plan).

### 6. Fewer user waits

- The build skill batches: the plan-approval question carries product's
  open questions and the plan's "Open items for the user" in one prompt.

## Files (owners for the build waves)

| Wave | Agent | Owns |
| --- | --- | --- |
| 1 | **scripts** (sonnet · high) | `scripts/plan-tasks.sh` (new), `scripts/watch-build.sh` (new), `teammate-idle-gate.sh`, `task-completed-gate.sh`, `ac-check.sh`, `lib.sh` (task-list readers: `team_tasks`, `ready_tasks`), `make-briefs.sh`, `context.sh`, `status.sh`; `tests/hooks-selftest.sh`, `scripts-selftest.sh`, `lib-selftest.sh`, new `tests/tasks-selftest.sh` |
| 1 | **templates** (sonnet · medium) | `skills/kickoff/templates/phase/dev-plan.md` (`Blocked by:` field, label note), `templates/standard/*` if they carry tasks |
| 2 | **prompts** (opus · high) | `agents/{product,lead,senior}-engineer.md`, `skills/build/SKILL.md` (spawn template, task creation, idle handling, split, batched questions), `skills/status/SKILL.md`, `skills/kickoff|signoff/SKILL.md` mentions |
| 3 | **evals** (sonnet · high) | new cases + fixture tweaks |
| 3 | **docs** (sonnet · medium) | README (How it works, Configuration, "What makes it fast"), `docs/dev-plan-v0.6.md` (this plan, with the measurements), `plugin.json` 0.6.0 |
| 4 | **reviewer** (sonnet · high, read-only) | fresh-eyes pass over the diff |

Branch `v0.6` from `v0.5.1-plan-review` (keeps 8fcf0f2). Gate after each wave:
`bash tests/run-all.sh` (both TMPDIR modes), `claude plugin validate` (strict
and marketplace), `git diff --stat` per agent.

## Verification

**Self-tests (new):**
- `plan-tasks.sh`: labels, `T<n>` fallback (plan-global), `Blocked by:`
  mapping, an unknown or duplicate label → exit 1, `[chore]` lines for the
  lead, CRLF plans, a plan with no `Blocked by:`, a title that starts with
  "S3 bucket" (no colon → not a label), every subject accepted by the
  task-created gate's rule.
- `task-completed-gate.sh`: the unblocked-owners `systemMessage` on a pass;
  `[chore]` still runs typecheck + lint under the tests-only default.
- Idle gate: with a fake `~/.claude/tasks/<team>/` (payload gains
  `team_name`): ready task → exit 2 with the task in the message; only
  blocked tasks → exit 0; `in_progress` → exit 2; a missing blocker id counts
  as completed; the lead → exit 2 only when an engineer's ready task has
  nothing in progress; three nudges then the escalation row, refusals up to
  six, then exit 0; the `.tasks` state file is separate from the dirty-files
  count; dirty files still take priority; no team dir or a jq failure → old
  behaviour byte-identical (the existing idle tests send no `team_name` and
  keep passing unchanged).
- `ac-check --tests-only` skips typecheck and lint; the task gate default is
  tests-only and `PLUMBLINE_TASK_CHECKS=full` restores both.
- `make-briefs`: core + per-task files, only the task's criteria and screens,
  the >20 KB warning, briefs without a Tasks section unchanged.
- `status.sh` team line (and none without a task dir).
- `watch-build.sh`: with a fake task dir and a repo where one owner has a
  ready task and no changes for 10 minutes → a `STALLED:` line; an owner
  with a fresh commit → none; `--sleep 0` in tests.
- Compatibility: a feature without `Blocked by:` lines and a run without a
  task list behave as in v0.5 except the tests-only default.

**Evals (3 runs each; new):**
- `senior-continues-to-next-task`: a brief with two ready tasks; graders:
  both tasks' test files written in one run (file_exists), task 1's test
  before task 2's (trace order), the final message is not an announcement
  (LLM). (Evals have no Bash or Task tools, so claiming is proven in the live
  run, not here.)
- `triage-splits-big-request`: a whole-module request → `Split:` line with
  ≥ 2 slices and `Size: Full` (regex); `triage-standard-screen` stays
  unsplit.
- `lead-plans-mock-first`: a plan whose UI workstream depends on the API:
  UI tasks mention a mock/contract and `Blocked by:` lines exist (regex);
  tasks ≤ 12.
- `lead-labels-and-dependencies`: every task has a label and dependent tasks
  have `Blocked by:` (regex), `Status: DRAFT` kept.
- Reruns (prompts changed): `triage-*`, `product-writes-spec`, `lead-*`,
  `senior-*`, `build-quick-dispatches`, `quick-review-loop`. Every case must
  hold its v0.5 score. About $35–45 at list price.

**Live run:** re-run the DineFlow staff portal on v0.6 as a fresh feature
slice (triage should split it; slice 1 ≈ sign-in + queue, ~25–30 criteria;
3–4 engineers). Measure with the hook log: no agent-idle gap over 5 minutes
with tasks ready, pre-build under 50 minutes, build under 100 minutes, checks
under 25% of engineer active time, briefs core ≤ 15 KB and task files ≤ 20 KB,
context resets ≤ 2 per engineer. Record it in `docs/evals/eval-v0.6.md`.

## Defaults this plan sets (approving the plan approves them; say if you'd change one)

- **D1** Feature cap: ~30 criteria and ~6 screens; bigger requests are split
  into ordered slices and slice 1 is built.
- **D2** Per-task checks run the task's tests only (a `[chore]` keeps
  typecheck + lint); typecheck, lint and the full suite run once per
  workstream and at signoff (`PLUMBLINE_TASK_CHECKS=full` restores the old
  behaviour).
- **D3** E2E tests are written in red but run at green, once per task.
- **D4** The idle gate nudges three times, escalates, keeps refusing up to
  six times, then allows (safety valve); the main session's watchdog loop
  (every 10 minutes) messages any stalled teammate regardless.
- **D5** Team size by load, decided by the lead when it plans: a surface
  with more than ~5 tasks gets two engineers with disjoint globs; max stays
  4 (triage's `Engineers:` stays by file areas).
- **D6** Mock-first is the rule for any task that depends on another
  workstream's unfinished output.

## Not in scope

- Changing models or effort (v0.4b/v0.5 settings stay).
- Agent-team internals we can't control (idle semantics, inbox delivery).
- The DineFlow run already in progress: it finishes on v0.5 with manual
  nudges; v0.6 is for the next feature.
