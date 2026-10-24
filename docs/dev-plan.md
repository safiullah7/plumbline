# Plumbline dev plan: v0.1.2 → v0.4

Status: READY for v0.1.2-v0.3 (approved 2026-10-24; corrected after
verification, see "Corrections after verification"). v0.4: DRAFT, awaiting approval.
Progress:
- v0.1.2 merged (PR #2).
- v0.2 merged (PR #3): evals 0.84 → 1.00, live smoke 11/11.
- v0.3 built on branch `v0.3`. Self-tests pass. Evals: all 10 rerun or new cases
  score 1.00 with no regressions; the memory case rose from 0.89 on v0.2 to 1.00
  (docs/evals/eval-v0.3.md). Live smoke test and PR pending.
- v0.4a built on branch `v0.4a` (steps A1-A11 done: helpers, ac-check, templates,
  agents, build skill, kickoff.sh, layout, locks, docs). Evals, live smoke test and
  PR pending. v0.4b not started.
- Team token benchmark still pending.
Owner: Safi. Written 2026-10-23 from the plugin review and the live smoke test;
v0.4 added 2026-10-24.

## Goals

1. Fix the two confirmed bugs (Temp-path bypass, invisible idle escalation).
2. Make every role work from a method, not just a brief: discovery for product,
   a design loop for UX, task-system features for the lead, a start routine for
   engineers, evidence-based QA.
3. Cut token use per phase by roughly half **without lowering output quality**.
4. Prove each release on a fresh repo with real teammates before tagging it.
5. (v0.4) Right-size the process to the task: a small fix shouldn't pay for a
   design phase, a QA team and ten documents, and a big feature shouldn't skip
   them.

## Non-negotiables

- **Quality first.** No token-saving change ships unless the plugin evals and
  the fresh-repo smoke test score the same or better with it than without it.
  If a change saves tokens but loses a check, it is reverted, not tuned.
- **Gates stay deterministic.** Anything that decides pass/fail is a script
  (bash + jq), never model judgement.
- **Nothing in the repo changes behaviour silently.** Every hook change has a
  self-test case; every skill change has an eval case.
- **Commits credit only Safi.** No co-author trailers or generated-with footers.
- Branch per release (`v0.1.2`, `v0.2`, `v0.3`) from `main`; PR per release;
  Safi merges.

## Facts the plan relies on (verified against Claude Code docs, 2026-10-23)

| Fact | Consequence for the plan |
| --- | --- |
| `TeammateIdle`/`TaskCompleted` command hooks only support exit codes, `continue`, `stopReason`; no path to message the lead | Escalations must go to a file (`questions.md`) and via the teammate itself |
| `TaskCreated` hook exists; exit 2 blocks creation | Gate AC IDs at creation, not only completion |
| Tasks support dependencies; blocked tasks cannot be claimed | Encode contracts-first and integration order as dependencies |
| `SessionStart` hooks may return `additionalContext`; only `SubagentStart` is documented to fire for in-process teammates (on each new message, de-duplicated, re-injected after compaction); `additionalContext` is capped at 10,000 chars | Inject phase, status, ownership row, open questions: SessionStart for the lead, SubagentStart for teammates |
| A plugin agent's `skills:` is **not** applied when it runs as a teammate | Agent bodies must invoke skills explicitly |
| Plugin agents ignore `permissionMode`, `hooks`, `mcpServers` | Don't rely on them; keep gates in `hooks/hooks.json` |
| `${CLAUDE_PLUGIN_DATA}` persists across versions; `${CLAUDE_PLUGIN_ROOT}` doesn't | Hook state lives in `CLAUDE_PLUGIN_DATA` |
| `autoCompactWindow`, `effort`, `model`, `memory`, `experimental.cacheTtl` supported in plugin agents | Use them for context and cost control |
| `claude plugin eval` exists (v2.1.269+) | Behavioural regression suite for skills and agents |
| Teams only spawn in interactive sessions | Live tests are run by Safi from a launch line; the plan ships the exact line and prompt |

## Corrections after verification (2026-10-24)

The roadmap was checked task by task against the code and the docs. These
corrections override the task tables below where they differ.

- **Releases branch from `main`** once the previous release's PR is merged
  (PR #1 merged 2026-10-24).
- **New bug, fixed in v0.1.2:** the dev-plan template had no Ownership row for
  QA, so during READY the ownership guard blocked every QA write.
- **Shared files.** `shared_path` in `lib.sh` lists the files anyone may write:
  `questions.md` and agent memory, plus `progress.md`, `briefs/` and
  `acceptance-criteria.json` from v0.2. The ownership guard allows them; the
  idle gate ignores them, so hook-written files can't bounce product and
  design.
- **Escalation row.** Create `questions.md` with its header if it's missing,
  number rows max + 1, keep the file's line endings, and de-duplicate on an
  `idle-gate <sig>` marker.
- **`/plumbline:signoff` and `/discover` are user-only** (they set
  `disable-model-invocation`), so tests check `signoff-check.sh` and the
  `questions.md` row directly, not the skill.
- **TaskCreated** fires for lead-created tasks, which have no `teammate_name`.
  Gate every creation during READY, and allow a `[chore]` prefix for
  coordination tasks with no AC.
- **Context injection:**
  - SessionStart for the lead, SubagentStart for teammates;
  - teammate name taken from the agent ID;
  - never exit 2;
  - silent without `jq`.
- **The task list file format is undocumented.** `status.sh` reads docs and git
  only, and the lead uses TaskList.
- **Templates for v0.2:**
  - AC priority becomes P0/P1/P2, with status taken from qa-report
    Traceability;
  - spec "Out of scope" becomes "Non-Goals", with no separate open-questions
    section;
  - ux Screen inventory gains a "Use cases" column;
  - Contracts becomes a `Contract | Path | Consumers` table;
  - prototypes paste the token block from `docs/product/<area>/tokens.css`;
  - bug statuses are OPEN, FIXED, VERIFIED, WONTFIX.
- **Skills from other plugins** (`frontend-design`, `agent-browser`) are used
  only if installed; fallback is `npx playwright`.
- **Evals:**
  - written first in v0.2, and a v0.1.2 baseline is recorded before any token
    change;
  - teams can't run under eval, so agent cases use subagents and gate cases
    stay in the bash self-test;
  - `evals/results/` is gitignored;
  - runs use `--no-publish`, `--runs 1` for routine runs and `--runs 3` before
    a release, within the Max plan's usage.
- **`memory: project`** is already on five agents. PL-072 adds only the
  `decisions.md` fallback.
- **Validation** uses `--profile directory` (license and icon) and `--strict`
  (new frontmatter).

---

## Release 1: v0.1.2 — bug fixes (small, ship first)

Branch `v0.1.2`. Target: same day.

### W1 Hooks (owner: lead session)

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-001 | `norm_path`: canonicalise through the Windows form (`cygpath -u "$(cygpath -m "$p")"`), fall back unchanged when cygpath is absent | Self-test "Windows path, foreign file" passes with `TMPDIR` set to `/c/Users/.../Temp` **and** unset; non-Windows path unchanged |
| PL-002 | Idle gate give-up: append `ESCALATED` row to the phase `questions.md` (`From: hooks`, `To: lead`, the file list) instead of relying on `systemMessage`; keep `systemMessage` as a bonus | New self-test case: after the 3rd idle, `questions.md` contains one ESCALATED row naming `src/a/draft.txt`; running again does not duplicate it |
| PL-003 | Idle gate 2nd push-back text: "If you can't fix this, SendMessage the lead now with this exact list: …" | Self-test asserts the 2nd stderr contains "SendMessage the lead" |
| PL-004 | Idle counter state moves from `TMPDIR` to `${CLAUDE_PLUGIN_DATA:-$TMPDIR}/plumbline-idle` | Self-test sets `CLAUDE_PLUGIN_DATA` and asserts the key file is created there |
| PL-005 | `tests/hooks-selftest.sh`: add the cases above; run the whole suite twice, once with `TMPDIR` pointing at Windows Temp | `0 failed` in both runs on Windows (Git Bash), macOS, Linux |
| PL-006 | Add `LICENSE` (MIT, Safi) at repo root and `license` in `plugin.json`; bump version to 0.1.2 | `claude plugin validate --profile directory` shows no LICENSE_MISSING |
| PL-007 | Dev-plan template gets a `qa` Ownership row; lead body keeps rows for product, design and qa | Template review |
| PL-008 | `shared_path` in `lib.sh`, used by the ownership guard and the idle gate | Self-test: a dirty `questions.md` doesn't bounce its owner |
| PL-009 | `.gitattributes` pins `*.md` and `*.json` to LF | `git ls-files --eol` shows `i/lf` for templates |
| PL-009a | Smoke test moves into `tests/smoke/` (prompt + README) with a git-based integrity check instead of hard-coded hashes | Smoke Part 1 shows CLEAN, MATCHES REMOTE, version and tree hash |

### Verification for v0.1.2

1. `bash tests/hooks-selftest.sh` → `0 failed` (both TMPDIR variants).
2. `claude plugin validate ./plugins/plumbline` and `.` → pass.
3. Fresh-repo smoke test (`tests/smoke/README.md`), Steps 1–4 all PASS **plus** new Step 5: after eng-a gives up, `questions.md` has exactly one ESCALATED row naming its file.

---

## Release 2: v0.2 — methods, gates and token efficiency

Branch `v0.2`. Six workstreams; W2–W5 can run in parallel, W6 after W2, W7 last.

### W2 Hooks and context injection

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-010 | `TaskCreated` gate (`scripts/task-created-gate.sh`): during READY, refuse tasks whose subject lacks `AC-nn-nnn` | Self-test: untagged create → exit 2 with message; tagged → 0; DRAFT → 0 |
| PL-011 | `SessionStart` hook (`scripts/session-context.sh`): emit `additionalContext` with phase path, `Status`, the caller's Ownership row (by `agent_type`/name, if any), count of OPEN/ESCALATED questions and the ANSWERED rows mentioning the caller's globs; ≤ 60 lines | Self-test: output is valid JSON, ≤ 60 lines, contains phase and status; silent (exit 0, no output) when no `.claude/current-phase` |
| PL-012 | Gate timing: task gate prints `typecheck 12s · lint 4s · tests 9s` on success to stderr only when `PLUMBLINE_HOOK_TIMING=1` | Self-test asserts line present with the flag, absent without |
| PL-013 | Compaction guidance: add to every agent body one line, "On compaction keep: modified files, test command, current task ID, open questions" | Review |

### W3 Deterministic status and sign-off

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-020 | `scripts/ac-json.sh`: derive `acceptance-criteria.json` (`[{id, useCase, priority, status}]`) from the Markdown table; idempotent | Self-test with the template + 3 rows → valid JSON, 3 entries |
| PL-021 | `scripts/status.sh`: prints AC coverage (AC IDs vs test names found by grep `AC-nn-nnn` in test files), open bugs by severity, OPEN/ESCALATED questions, task list summary (from `~/.claude/tasks/<team>/` when present), dirty files per owner | Self-test on a fixture; output ≤ 40 lines |
| PL-022 | `/plumbline:status` skill (`disable-model-invocation: true`) that runs `status.sh` and shows the result | Manual |
| PL-023 | `/plumbline:signoff`: run `scripts/signoff-check.sh` first; the model only acts on its result (list gaps or open the PR) | Eval: with one AC lacking a test, the skill stops and names the AC; with a clean fixture it proceeds |
| PL-024 | `/plumbline:handoff` skill: writes `progress.md` (done, next, blockers, resume prompt), commits docs only, prints the resume prompt | Eval: file created with the four sections |

### W4 Product engineer method

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-030 | `spec.md` template: add Non-Goals, Requirements by priority (P0/P1/P2 with the "if cutting it still solves the core problem it isn't P0" rule), Success metrics (metric, target, window), Open questions (owner, blocking?) , "What we learned" | Template review; kickoff copies it |
| PL-031 | `vision.md` Phases table: add "Outcome" and "Why next" columns | Template review |
| PL-032 | Product agent body: research steps (read existing code and data model for the area; scan prior phases' `questions.md`/`signoff.md`; WebSearch 2–3 best-in-class products; write "What we learned"), AC rules unchanged, maintain `docs/product/<area>/decisions.md` | Eval: given a stub repo and a prompt to write a spec, the output includes Non-Goals, P0 list, metrics and a learned section, and never invents a product decision (escalates instead) |
| PL-033 | `/plumbline:discover` skill: interview via `AskUserQuestion` (users, jobs, hard parts, permissions, failure cases, what "done" means), then draft `spec.md`; `disable-model-invocation: true` | Eval: the skill asks before writing; the spec cites the answers |

### W5 UX engineer method

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-040 | `ux.md` template: add "Design brief (pass 1)": 4–6 named colours, type roles, spacing scale, ASCII wireframes, 3 principles; "Critique (pass 2)": screenshot paths and what changed | Template review |
| PL-041 | `design-principles.md` "Patterns to avoid": add the anti-slop list (identical rounded cards, uniform shadows, gradient washes, tracked-out all-caps eyebrows, arrows on buttons, two near-identical fonts, colour-only meaning) | Template review |
| PL-042 | UX agent body: invoke the `frontend-design` skill explicitly (frontmatter `skills` is ignored for teammates); prototype loop = screenshot each prototype at 390 and 1280 px with `agent-browser`/Playwright, save to `prototypes/shots/`, critique against the brief, fix, repeat once; own `tokens.css` as the single source of truth | Eval: prototypes reference `tokens.css`; `ux.md` has both passes filled; shots exist |
| PL-043 | Screenshot token policy in UX and QA bodies: save shots to disk; view an image only for a failed check or the final critique | Review |

### W6 Lead, engineers, QA, reviewer

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-050 | Lead body: create tasks with dependencies (contracts → API → UI → e2e); reconcile `TaskList` with `git log` whenever a teammate goes idle; pre-approve common permissions before spawning; keep `effort: xhigh` for planning, note that build sessions may run at `high` | Eval: given a dev plan, the lead's task list has dependency edges |
| PL-051 | Dev-plan template: add "Decisions (ADR)" table and "Per-workstream briefs" section listing `briefs/<teammate>.md` | Template review |
| PL-052 | `scripts/make-briefs.sh`: from `dev-plan.md`, `acceptance-criteria.md`, `ux.md`, build `briefs/<teammate>.md` with that teammate's Ownership row, tasks, only the AC rows those tasks cite, the screens it touches, the contracts it consumes; lead runs it when setting READY | Self-test on a fixture: brief contains its own AC rows and none of the other workstream's |
| PL-053 | Senior engineer body: start routine (read brief, `git log -20`, `progress.md`, run baseline test command, then claim); test-first per AC; **never edit or delete existing tests**; append two lines to `progress.md` before going idle; `autoCompactWindow: 200000`; use a subagent for library research | Eval: engineer refuses a prompt to "just delete the failing test" |
| PL-054 | Split QA: `qa-engineer` (opus, writes `test-plan.md`) and `qa-runner` (sonnet, executes: automated suites, browser journeys at two viewports, axe scan per screen, screenshot per key screen compared with the prototype, bugs with evidence paths, pass^k regression) | Eval: runner output has evidence paths for every bug; verdict logic unchanged |
| PL-055 | Code reviewer: input limited to diff + AC list + contracts; report Critical/Warning only unless asked; lead spawns two reviewers (security lens, contract lens) for HIGH workstreams | Eval: a diff with an unscoped tenant query yields a Critical |
| PL-056 | Model/effort table in README: who runs on what and why; reviewer on sonnet for NORMAL, opus for HIGH | Review |

### W7 Plugin evals and quality guard

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-060 | `claude plugin eval init`; write 12–20 cases: kickoff file set; untagged task refused; engineer won't touch `contracts/`; product escalates instead of guessing; signoff stops on gaps; discover asks first; status output shape | `claude plugin eval` passes all; baseline run recorded in `docs/evals/baseline-v0.2.md` |
| PL-061 | Token guard: record tokens per role for the fresh-repo smoke test before and after W2/W6 (from the Claude Code session cost view); ship only if evals ≥ baseline | Numbers in `docs/evals/tokens-v0.2.md` |
| PL-062 | `.claude-plugin/icon.png` (512 px square), version 0.2.0, README updated for new skills | Validate shows no icon warning |

---

## Release 3: v0.3 — deeper loops

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-070 | Visual regression: `scripts/visual-diff.sh` comparing QA screenshots with prototype shots (pixelmatch or Playwright `toHaveScreenshot`) with thresholds; results into `qa-report.md` | Fixture test with one intentional change flagged |
| PL-071 | Accessibility gate: axe results summarised into `signoff.md` Design findings; any serious/critical violation blocks signoff | Fixture test |
| PL-072 | Product memory: `memory: project` on product and UX agents plus explicit read/update of `decisions.md` (memory for teammates is unconfirmed; the file is the fallback) | Eval: a decision made in phase N is cited in phase N+1's spec |
| PL-073 | Prompt caching: `experimental.cacheTtl: 1h` on all agents; agent bodies ordered stable-first | Review; token numbers in `docs/evals/tokens-v0.3.md` |
| PL-074 | `/plumbline:phase-next`: proposes the next phase from signoff findings, open bugs and vision outcomes; product engineer decides | Eval |

**As built (2026-10-24), after a design review against the code:**
- **Fixed a v0.2 bug:** the `qa-runner` teammate had no Ownership row.
- **Screenshots and scans:**
  - `capture.mjs` takes screenshots and runs axe;
  - Playwright is optional (Chrome or Edge, no browser download);
  - without it the script prints SKIPPED with the install command.
- **Visual comparison:**
  - `visual-diff.mjs` uses Node built-ins only, with its own PNG decoder, tested
    against a real browser screenshot;
  - it compares 8×8 block averages over content blocks;
  - above 20% a screen is flagged for design review, not made a bug.
- **Accessibility gate:**
  - `qa-summary.sh` writes the Visual comparison and Accessibility tables;
  - signoff blocks on serious or critical violations, and on a missing scan
    unless qa-report.md has an `Accessibility waived:` line.
- **Next phase:** `phase-evidence.sh` and `/plumbline:phase-next`; signoff.md
  gains a Success metrics results table.
- **Context:** `context.sh` tells every agent where the plugin's scripts are.
- **Memory:** delivered in v0.2; v0.3 adds the eval that proves it.
- **Caching:** delivered in v0.2; measurement deferred with the team benchmark.

---

## Release 4: v0.4 — adaptive delivery (right-size every task)

**The detailed, step-by-step plan for this release is
[`docs/dev-plan-v0.4.md`](dev-plan-v0.4.md).** It has the exact formats,
script interfaces, build order, tests and definition of done; this section is
the summary.

**Problem.** Every request gets the full process today:
- kickoff creates 10+ documents;
- product, UX, lead, engineers and QA all take part;
- an agent team runs it, which needs the experimental launch flag and costs the
  most.

A one-line bug fix pays for all of that.

**Goal.** One entry point, `/plumbline:build <request>`. The product engineer
triages the request and the plugin picks the process to match: the size of the
work (Quick, Standard, Full) **and** the kind of software it touches (its
surfaces: web, mobile, API, CLI, library, data, AI, infra; see "Project
awareness" below). From those it decides which roles take part, whether UX is
needed, how many engineers, what evidence QA must produce, whether to keep docs,
and team or subagents. It asks the user only when it's genuinely unclear.
Quality bars hold at every size and for every surface: observable acceptance
criteria, tests named after them, evidence that fits the surface, a review
before done, and a PR the user merges.

### Verified constraints (Claude Code docs, 2026-10-24)

| Fact | Consequence |
| --- | --- |
| Subagents can start subagents, up to 3 levels below the main conversation | The lead can run as a subagent and dispatch its engineer and reviewer itself: no agent team for small work |
| AskUserQuestion is removed from every subagent | Triage confirmation and any question to the user happen in the main session (the build skill), never inside a subagent |
| A dispatch can override the subagent's model | Triage runs on sonnet; judgement-heavy work keeps opus |
| Hooks gate only teammates (ownership, task gates) | Subagent paths get the same checks from a script the lead must run (`ac-check.sh`) and from the reviewer |
| Teams need `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` at startup | Quick and Standard never need it. Full stops with the launch command if teams are off |

### Sizes

| Size | Typical work | Who takes part | Docs | Runs as |
| --- | --- | --- | --- | --- |
| **Quick** | A bug fix or small change inside one module; no new screen, flow, schema or shared contract | Product (triage and criteria) → lead → 1 engineer → reviewer | **No folder.** Criteria and tests go in the PR body, plus one row in the module's `changes.md` if that module folder already exists (never created for Quick) | Subagents only |
| **Standard** | One feature in one module | Product, lead, 1–2 engineers, QA runner. UX only if screens, flows or visible copy change | **A new feature subfolder inside the module's folder.** The module folder is created first if it doesn't exist. Slim templates (`Profile: standard`) | Subagents; a team only if there are 2 engineers and teams are on (otherwise sequential subagents) |
| **Full** | A new module, or a big feature (multiple screens, cross-module work, data migrations, auth or billing) | Everyone, as today | **A new module:** a new module folder with its module docs, and the feature subfolder inside it. **A big feature in an existing module:** a feature subfolder there. Full templates (`Profile: full`) | Agent team with all gates |

### Docs layout (modules and features)

```
docs/product/
  rooms/                        <- one folder per module
    vision.md                   module docs: who it's for, problem, principles, features table
    design-principles.md        (+ tokens.css once the UX engineer creates it)
    decisions.md
    changes.md                  one row per Quick change in this module
    07-room-schedules/          <- one subfolder per Standard or Full feature
      spec.md, acceptance-criteria.md, dev-plan.md, questions.md, ...
      contracts/  prototypes/  briefs/  qa/
  billing/
    ...
```

- **One folder per module** in `docs/product/`. The module docs (vision,
  design-principles, decisions, changes) live in it and carry across all of the
  module's features.
- **One subfolder per Standard or Full feature**, named `<nn>-<feature-slug>`.
  `nn` is a repo-wide sequence (the highest number in any module, plus 1), so AC
  IDs (`AC-<nn>-<nnn>`) and the tests named after them never collide across
  modules. They also still match every existing gate and pattern.
- **Where the work goes:**

  | Task | Folder |
  | --- | --- |
  | Quick | no folder |
  | Standard | feature subfolder in the module; module folder created if missing |
  | Full, new module | new module folder, then the feature subfolder |
  | Full, existing module | feature subfolder, full profile |

- `.claude/current-phase` points at the active feature folder, so the hooks,
  `status.sh`, `signoff-check.sh` and the briefs work unchanged.
- **Backward compatible:** repos from v0.1–v0.3 keep
  `docs/product/<area>/phases/<phase>/`. Scripts find the module folder from
  either layout: the parent of the feature folder, or its grandparent when the
  parent is `phases/`. Nothing is moved.
- **Wording:** "feature" replaces "phase" in docs and user-facing text. The
  existing command names stay.

### Triage rules (in the build skill and the product engineer's triage mode)

- **Module first.** Work out which module the request belongs to. Match it
  against the folders in `docs/product/` and the code layout. Answer with an
  existing module's name, or a proposed new module name with a reason. Ask when
  it could belong to two modules, or when it's unclear whether it's a new
  module.
- **Full** if any of these apply:
  - a new module;
  - 3 or more screens;
  - a data migration;
  - a change to the auth or permissions model;
  - billing;
  - work across modules;
  - about 10 or more acceptance criteria.
- **Quick** if all of these apply:
  - one module and at most 3 criteria;
  - no new screen or flow;
  - no schema change;
  - no change to a contract another workstream depends on.
- **Standard** otherwise.
- **UX** is needed if and only if the task adds or changes a screen, a flow, or
  visible copy beyond a label. Backend-only work never involves UX.
- **Engineers:** one per independent file area, at most 4. Quick is always 1.
- **Docs:** placed by the layout table above.
  - Quick: none.
  - Standard: a feature subfolder (slim) in the module.
  - Full: a new module folder or a feature subfolder (full).
  - The first time Plumbline runs in a repo with no `docs/product/`, it asks
    whether to keep feature docs at all.
- **Ask the user only when:**
  - the request is too vague to write observable criteria;
  - triage can't decide between two sizes;
  - the module is unclear (existing or new, or which one);
  - the size is Full (confirm the bigger commitment, and that teams are on);
  - the docs choice is open.

  Otherwise the skill shows the decision and proceeds. `PLUMBLINE_CONFIRM=always`
  makes it always confirm.
- **Fixed output block**, which the evals grade:
  ```
  Plumbline triage
  Size: Quick | Standard | Full
  Module: <name> (existing | new)
  Folder: none | docs/product/<module>/<nn>-<feature-slug>/
  Surfaces: <from project.md, e.g. api, web-ui>
  Roles: <e.g. product, lead, 2 engineers, UX (web-ui), QA runner>
  Evidence: <per surface, e.g. contract tests; browser screenshots + axe>
  Engineers: <n>
  Docs: none | slim | full
  Team: no | yes
  Why: <one line>
  ```
- **Escalation mid-way:** if Quick or Standard work grows past its limits, the
  lead stops and re-triages; it never quietly expands the scope.

### Flows

1. **Quick:**
   1. The triage subagent (sonnet) writes 1–3 acceptance criteria with IDs
      `AC-<yymmdd>-<nn>`. These are unique per day and match the existing gate
      and test-name patterns.
   2. The lead subagent creates a branch `quick/<slug>` and dispatches one
      senior engineer subagent (test-first, tests named after the IDs).
   3. The lead runs `ac-check.sh <IDs>` and dispatches the code reviewer
      (sonnet). Critical findings are fixed and checked again.
   4. The lead commits by path, opens a PR with the request, criteria, tests and
      review in the body, and adds a row to the module's `changes.md` if the
      module folder exists. It never creates a folder. It never merges.
2. **Standard:**
   1. `kickoff.sh <module> <feature-slug> --profile standard [--ux]` creates
      the feature subfolder (next repo-wide number) inside the module's folder,
      creating the module folder and its module docs first if they're missing.
   2. Product writes the slim spec and criteria. UX writes `ux.md` and one
      prototype only when needed.
   3. The lead writes the dev plan, and the user approves it (one question).
      The plan is then READY and briefs are generated.
   4. The build runs as 1–2 engineer subagents, or a team if available.
   5. The QA runner runs the criteria, then `signoff-check.sh`, then the PR.
3. **Full:** today's flow (kickoff → discover → spec, UX, test plan → plan →
   team build → QA → signoff).
   - **For a new module,** `kickoff.sh <module> <feature-slug> --profile full
     --new-module` creates the module folder and its module docs first; the
     product engineer then writes the module's vision before the feature spec.
   - **For a big feature in an existing module,** only the feature subfolder is
     created.
   - If teams are off, it stops with the launch command.

### Project awareness: any kind of software, not just a web app

**Problem (from an audit of every agent, template and script, 2026-10-24).**
The gates, docs and evidence model are general, but *what counts as evidence*
and *which roles take part* are hard-coded for a web app:

- the QA runner and QA engineer assume browser journeys at 390/1280 px,
  Playwright, URLs and axe;
- the UX engineer assumes HTML prototypes, `tokens.css` and WCAG via axe;
- the reviewer's checklist starts with tenant isolation and "patient data";
- the lead's examples are `schema.prisma`, `apps/web/e2e` and appointments;
- the task gate defaults to `npm run typecheck/lint/test:ac`, one command for
  the whole repo;
- the signoff accessibility rule assumes axe results.

A mobile app, an API, a CLI, a data pipeline or an AI feature would get the wrong
instructions, or none.

**Goal.** The plugin knows what kind of software the repo is (its *surfaces*),
picks the roles for each task from the size **and** the surfaces, and every
role adapts its practice to the surface: the right prototype, the right
evidence, the right checks, the right review. Web stays first-class; nothing
about it is assumed.

#### Surfaces

| Surface | Examples | UX engineer | QA evidence (what the test plan must produce) | Reviewer focus, added to the base checklist |
| --- | --- | --- | --- | --- |
| **web-ui** | React, Next, Vue, server-rendered pages | Yes: HTML prototypes, CSS tokens | Browser screenshots vs prototype (`capture.mjs`, `visual-diff.mjs`), axe scan, journey tests | UI states, keyboard, contrast, XSS |
| **mobile-ui** | iOS, Android, React Native, Flutter | Yes: device-size mockups, platform conventions (HIG / Material) | Simulator or emulator screenshots (`xcrun simctl io … screenshot`, `adb exec-out screencap`) fed to `visual-diff.mjs`; flow tests (Maestro, Detox, XCUITest, Espresso, Flutter integration tests); a platform accessibility checklist | Offline and flaky network, permissions, lifecycle and background, battery, store rules |
| **desktop-ui** | Electron, Tauri, native | Yes | App screenshots through its test harness; accessibility checklist | Window states, keyboard, updates |
| **api** | REST, GraphQL, gRPC services | No (the lead reviews API design) | Contract tests against the schema (OpenAPI, GraphQL SDL, proto), negative and authorization tests, recorded request/response transcripts as evidence | Authorization on every endpoint, input validation, idempotency, migrations, tenant scoping when multi-tenant |
| **service** | Workers, jobs, queues | No | Job-level tests with recorded inputs/outputs, retry and failure cases | Idempotency, retries, dead-letter handling, observability |
| **cli** | Command-line tools | Light: the product engineer specifies help text, flags, exit codes, error messages | Golden-output tests, recorded sessions, non-interactive runs | Exit codes, stdout/stderr discipline, `--help`, no interactive prompts in scripts |
| **library** | SDKs, packages | No | Runnable doc examples, unit tests, a public-API diff (semver) | Breaking changes, naming consistency, error types |
| **data** | Pipelines, ETL, warehouse models | No | Runs on a sample dataset with row counts and schema diffs as evidence; re-run proves idempotency | PII handling, idempotency, backfills, partial failure |
| **ai** | Prompts, model calls, agents, RAG | Only when there's a conversational UI | An **eval set** (inputs with expected outputs or a rubric) with a pass threshold, a regression run on a golden set, prompt-injection cases, cost and latency budgets; non-determinism handled by seeded runs and pass-every-time | Prompt injection, data leakage, eval coverage, fallback behaviour, cost |
| **infra** | Terraform, Kubernetes, CI | No | Plan or dry-run output, policy checks | Blast radius, secrets, rollback |

A feature can span surfaces (an API plus a web screen). Roles and evidence are
the union.

#### Design

1. **Project profile:** `docs/product/project.md`, one per repo. A Surfaces
   table: `| Surface | Stack | Paths | Run / preview | Typecheck | Lint | AC tests | Evidence |`,
   plus `Multi-tenant: yes/no` and `Sensitive data: <kinds>`. It's the single
   place that says what the product is made of and how to check it.
2. **Detection, then confirmation:** `scripts/detect-project.sh` scans the repo
   (package.json and its framework dependencies, `pubspec.yaml`, `android/`,
   `*.xcodeproj`, `Package.swift`, `pyproject.toml`, `go.mod`, `Cargo.toml`,
   `*.csproj`, `build.gradle`, Dockerfiles, Terraform, notebooks, prompt and
   model folders) and proposes the table. The first run of `/plumbline:build`
   or `/plumbline:kickoff` shows the proposal and the user confirms or edits it
   in the main session; it's never guessed silently. Later runs read it.
3. **Roles from size × surfaces:** the triage block gains `Surfaces:` and
   `Roles:` lines (for example `Surfaces: api, web-ui` →
   `Roles: product, lead, 2 engineers, UX (web-ui), QA runner`). The build skill
   dispatches exactly those.
4. **Every agent gets a "By surface" section** in place of web-only text:
   - **QA engineer:** writes the Evidence column of the test plan from the
     table above, per AC; browser screenshots only for web-ui.
   - **QA runner:** executes per surface; for mobile it captures from the
     simulator or emulator and feeds the same `visual-diff.mjs`; for API it
     records transcripts; for AI it runs the eval set; it never asks for a URL
     when there isn't one, and records "not run" honestly when a tool is missing.
   - **UX engineer:** takes part only for UI surfaces; mobile prototypes are
     device-size mockups with platform conventions; accessibility by checklist
     where axe doesn't apply.
   - **Code reviewer:** base checklist (validation, errors, tests, security,
     readability) plus the surface rows; tenant isolation only when
     `Multi-tenant: yes`.
   - **Lead:** per-workstream checks from the profile; HIGH-risk list by
     surface; generic examples.
   - **Product engineer:** verification by the surface's evidence, not "walk
     the browser"; examples drawn from the project, not a clinic.
   - **Senior engineer:** tests named after ACs in the stack's convention
     (`AC-01-001` in strings, `AC_01_001` where identifiers can't contain dashes).
5. **Gate adapters per stack:** `scripts/ac-tests/<stack>.sh "<IDs>"` for
   node, pytest, go, cargo, dotnet, gradle, flutter and swift, plus a generic one
   that takes a command template. Each translates the IDs into the runner's
   filter, runs it, and fails when any ID has no passing test. The task gate and
   `ac-check.sh` pick the workstream's checks from the profile (by the files the
   workstream owns), so a Flutter + Go monorepo is gated per workstream.
6. **Templates by surface:** `templates/surface/<surface>/` overlays that
   kickoff applies for the feature's surfaces: a mobile `ux.md` (device sizes,
   platform conventions) and accessibility checklist; an API `contracts/`
   section with the schema; an AI `test-plan.md` eval-set section and a `spec.md`
   model/prompt section; a CLI usage spec. Web keeps today's templates.
7. **Signoff accessibility rule by surface:** web-ui needs axe rows or a waiver;
   mobile-ui and desktop-ui need checklist result rows or a waiver; surfaces
   with no UI are exempt.
8. **Visual comparison for mobile:** `visual-diff.mjs` already compares any two
   PNGs of the same size, so emulator screenshots work as they are; a
   `capture-mobile.sh` helper wraps `xcrun simctl` and `adb` when present.
9. **Generic wording:** clinic, patient, receptionist and appointment examples
   leave the agent bodies; they stay only in the eval fixture.

#### Tasks (project awareness)

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-094 | `templates/project.md` and `scripts/detect-project.sh`: proposes the Surfaces table from manifests; `project_surfaces()` and `surface_checks()` in `lib.sh` | Self-test on fixture repos: Node web, Flutter, Go API, Python data, a Node API + web monorepo, an AI service; each yields the right surfaces and checks |
| PL-095 | Gate adapters `scripts/ac-tests/{node,pytest,go,cargo,dotnet,gradle,flutter,swift,generic}.sh`; the task gate and `ac-check.sh` pick checks per workstream from the profile | Self-test per adapter where the toolchain is installed (Node, Python and Go at least), skipped with a note otherwise; each proves pass, fail and no-test |
| PL-096 | Triage adds surfaces and roles: the product engineer's triage mode reads `project.md`, the fixed block gains `Surfaces:` and `Roles:`, the build skill dispatches those roles | Triage evals per surface (below) |
| PL-097 | QA engineer and QA runner by surface: the evidence matrix in the QA engineer's body; the runner's per-surface execution, mobile capture, API transcripts, AI eval sets; `capture-mobile.sh` | Evals: a mobile feature's test plan asks for emulator screenshots and flow tests, not URLs; an API feature's plan has contract and authorization tests; an AI feature's plan has an eval set with a threshold |
| PL-098 | UX engineer by surface: UI surfaces only, mobile mockups and platform conventions, checklist-based accessibility | Eval: a mobile screen gets device-size mockups and a checklist, no axe |
| PL-099 | Code reviewer by surface: base checklist plus surface rows; tenant isolation only when the profile says multi-tenant | Evals: an API diff missing authorization is Critical; a CLI diff that prompts interactively is flagged; a single-tenant repo isn't told about tenants |
| PL-100 | Lead, product and senior engineer by surface: per-workstream checks, HIGH-risk list, verification by evidence, AC naming conventions; generic examples replace the clinic ones | Review; existing evals ≥ v0.3 |
| PL-101 | Surface template overlays (mobile, api, ai, cli) and the signoff accessibility rule by surface | Self-tests: kickoff with each surface produces its overlay; signoff passes a mobile feature with a checklist and no axe, and an API feature with no UI |
| PL-102 | Fixtures and evals for the surfaces: Flutter, Go API, Python data, AI service and CLI fixtures under `evals/_fixture/`; the cases above | New cases recorded at ≥ 2/3; all existing cases ≥ v0.3 |
| PL-103 | README: "Works with" section (surfaces and stacks), the evidence table; smoke test adds an API-only Quick task | Smoke rows PASS |

**Verification notes:** the mobile, API and AI commands in the adapters and
the runner's guidance are checked against the tools' current documentation
during implementation, and each adapter has a fixture test. The browser,
simulator and emulator parts can't run in evals; the self-tests and the live
smoke test cover them.

### Tasks (adaptive sizing and docs layout)

| ID | Task | Acceptance |
| --- | --- | --- |
| PL-080 | `/plumbline:build <request>` skill: dispatches triage, prints the triage block, applies the ask rules, routes to the Quick, Standard or Full flow; no-shell fallbacks like signoff | Evals PL-089 |
| PL-081 | Product engineer triage mode: the size rubric, UX/engineers/docs decisions, criteria for Quick, the fixed block, and "can't write observable criteria → say what's missing" | Triage evals |
| PL-082 | Lead quick mode: no phase folder, nested dispatch of 1 engineer and the reviewer, `ac-check.sh`, branch and PR, `changes.md` row, re-triage when the work grows | Quick-run eval; live check |
| PL-083 | `scripts/ac-check.sh <IDs>`: the task gate's typecheck, lint and AC tests as a script; the logic is shared with `task-completed-gate.sh` through `lib.sh` | Self-test: pass, fail and no-test cases |
| PL-084 | `scripts/kickoff.sh <module> <feature-slug> [--profile standard\|full] [--ux\|--no-ux] [--new-module]`: deterministic kickoff. It creates the module folder and module docs when missing (always with `--new-module`, and errors if the module already exists), then the feature subfolder `<nn>-<feature-slug>` with the next repo-wide number. It fills placeholders (`<phase>` → nn, `<Module>`/`<module>`), writes `Profile:` into the dev plan and the folder into `.claude/current-phase`. `/plumbline:kickoff <module> <feature>` calls it, with a by-hand fallback. `plan_profile()` in `lib.sh` | Self-test: Standard into an existing module, Standard creating a missing module, Full new module, Full in an existing module, numbering continues across modules, and `--new-module` on an existing module fails; the kickoff eval stays 1.00 |
| PL-085 | `templates/standard/` overlay: slim spec (Goal, Requirements, Business rules, Data and permissions, Non-Goals, Success metrics), slim test plan (traceability only), signoff without "Design verification" when there's no UX | Self-test; `signoff-check.sh` passes a clean standard phase without `ux.md` |
| PL-086 | Module templates: `templates/area/` becomes `templates/module/` (vision with a Features table, design-principles, decisions, and a new `changes.md` with Date \| Request \| ACs \| PR); the Quick AC ID format | Self-test |
| PL-087 | Senior engineer and QA runner work without a brief or phase folder (criteria come from the dispatch prompt); `context.sh` stays silent without a phase | Quick-run eval |
| PL-088 | Team detection: the build skill checks whether team tools are present; Standard with 2 engineers falls back to sequential subagents; Full stops with the launch command | Eval: Full without teams stops with the command |
| PL-089 | Evals, on a fixture with an existing `rooms` module folder. Triage cases: backend bug in rooms → Quick, no UX, 1 engineer, folder none; a rooms screen feature → Standard, module rooms (existing), UX yes, a folder inside `docs/product/rooms/`; CSV export API → UX no; booking system → Full, module new (e.g. appointments), UX yes, ≥2 engineers, a new module folder; a feature for a module with no folder yet → Standard, module new folder created; a vague request → asks first. Plus `build-quick-runs`: an engineer is dispatched, an AC-named test is written, no folder is created under `docs/product/`, the reviewer is dispatched, no merge | New cases recorded at ≥ 2/3; all existing cases ≥ their v0.3 scores |
| PL-090 | README (sizes table, `/plumbline:build` first in Use), version 0.4.0, smoke step for a Quick task through `/plumbline:build` without a team | Smoke: the Quick task ends with a PR and passing AC tests, and no team is created |
| PL-091 | Measure a Quick task with `tests/tools/token-report.sh` and record it in `docs/evals/tokens-v0.4.md` | Numbers recorded |
| PL-092 | Layout support in the scripts: `module_dir()` in `lib.sh` (parent of the feature folder, or grandparent under `phases/`); `phase-evidence.sh` and `/plumbline:phase-next` read the module's features, in both layouts; `context.sh` names the module; `next_feature_number()` scans every module | Self-test on both layouts; the phase-next eval stays 1.00 |
| PL-093 | Agents and skills use module and feature language and paths: the product engineer owns the module vision and decisions; the UX engineer owns the module's design-principles and tokens; `/plumbline:kickoff` takes `<module> <feature>`; the README shows the layout | Review; existing evals ≥ v0.3 |

---

## Fresh-repo smoke test (every release)

Run by Safi from PowerShell (teams need an interactive session):

```
Remove-Item -Recurse -Force D:\Repos\plumbline-smoke -ErrorAction SilentlyContinue; mkdir D:\Repos\plumbline-smoke | Out-Null; cd D:\Repos\plumbline-smoke; $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"; $env:CLAUDE_CODE_ENABLE_TODO_TOOLS="1"; $env:PLUMBLINE_HOOK_DEBUG="1"; claude --plugin-dir D:\Repos\plumbline\plugins\plumbline
```

The prompt lives in `tests/smoke/prompt.md` (moved into the repo in v0.1.2 so it is versioned). It must:

1. **Part 1**:
   - check the clone is clean, matches its remote, and has no installed copy of
     Plumbline that would fire the hooks twice;
   - record the version and tree hash;
   - validate the plugin and marketplace;
   - run the self-test in both TMPDIR modes.
2. **Part 2**: build the fixture (package.json, `test-ac.js`, `.claude/current-phase`, READY dev plan).
3. **Part 3 (live team)**: eng-a foreign write blocked; eng-b own write committed; tagged task completes; untagged task refused (v0.2: refused at *creation*); idle push-back twice then allowed; **v0.1.2+: ESCALATED row in `questions.md`**; **v0.2+: SessionStart context seen by a teammate; `/plumbline:status` output; `/plumbline:signoff` stops on the escalation**.
4. **Part 4**: table of check / expected / actual / PASS-FAIL, hook fire counts, log excerpts for failures.

A release is tagged only when every row is PASS on Windows (Git Bash). macOS/Linux runs of the self-test are required; the live test there is desirable.

### Final end-to-end test (v0.2 and v0.3): a real mini-phase

On a fresh repo (`D:\Repos\plumbline-e2e`): a tiny Node/TS app with one table (e.g. "clinic rooms"). Run the whole flow with the plugin: `/plumbline:kickoff rooms phase-01` → `/plumbline:discover` (Safi answers) → spec/UX/test plan → dev plan (2 engineers) → READY → build → QA → `/plumbline:signoff`. Pass criteria:

- every AC has a test named after it and all pass;
- `questions.md` has no OPEN/ESCALATED rows at signoff;
- QA report PASS with evidence paths;
- prototypes and the built UI match on the key screen within the visual threshold (v0.3);
- tokens per role recorded and compared to the v0.1.1 baseline run of the same mini-phase; quality rows must be equal or better.

---

## Order of work

1. v0.1.2 (W1) → smoke test → PR → merge.
2. v0.2: W7 evals first, with a recorded v0.1.2 baseline and a baseline mini-phase run; then W2 and W3 (they give the test harness its new checks), then W4/W5/W6, then rerun evals and the mini-phase e2e against the baseline → PR → merge.
3. v0.3: built and partly evaluated (Safi chose to build before using v0.2 on a
   real phase). Finish its evals, smoke test, then PR and merge.
4. v0.4, after v0.3 merges, as two PRs on one release so each half gets its
   own evals and smoke test:
   - **v0.4a, sizing and layout:**
     1. record v0.3 as the eval baseline;
     2. PL-083/084/085/086/092, the deterministic scripts, templates and the
        module/feature layout, with self-tests on both layouts;
     3. PL-081/082/087/093, the agents and module language;
     4. PL-080/088, the build skill;
     5. PL-089 evals; any existing case below its v0.3 score is fixed or reverted;
     6. PL-090/091 docs, smoke and measurement;
     7. PR, then stop for review.
   - **v0.4b, project awareness:**
     1. PL-094/095, the project profile, detection and gate adapters, with
        self-tests on fixture repos;
     2. PL-101, surface templates and the signoff rule;
     3. PL-096/097/098/099/100, triage and every agent by surface;
     4. PL-102 evals on the new fixtures; existing cases ≥ v0.4a;
     5. PL-103 README and smoke;
     6. PR, then stop for review.

## Risks

| Risk | Mitigation |
| --- | --- |
| Token savings from briefs hide context an engineer needed | Briefs always link to the full docs; eval cases include one task that needs a non-cited AC |
| Teammate hook semantics change (experimental feature) | Every hook has a self-test; the smoke test is rerun on each Claude Code upgrade |
| `SessionStart` output too long and crowds context | Hard cap of 60 lines enforced in the script and the self-test |
| Splitting QA into two agents loses continuity | Both read/write the same `test-plan.md` and `qa-report.md`; the planner's cases are the runner's checklist |
| `agent_type`-based identity spoofable by a stray subagent name | Ownership guard already requires a row in the Ownership table; document it |
| (v0.4) Triage sizes a task too small and skips UX or QA it needed | The triage block is shown before work starts; the lead re-triages when the work grows; boundary cases in the evals; `PLUMBLINE_CONFIRM=always` for cautious users |
| (v0.4) Subagent paths escape the hooks (they gate teammates only) | `ac-check.sh` (deterministic) and the code reviewer are required steps in the lead's quick mode, and the quick-run eval checks both happen |
| (v0.4) Nested subagents hit the 3-level limit | Quick and Standard stay at depth 2 (main → lead → engineer or reviewer); engineers in those modes do their own research instead of spawning more |
| (v0.4) Two entry points confuse users | `/plumbline:build` becomes the documented start; `/plumbline:kickoff` remains for starting a Full phase by hand |
| (v0.4) AC IDs collide across modules (tests are named after them) | Feature numbers are a repo-wide sequence, so `AC-<nn>-<nnn>` is unique across modules; Quick uses `AC-<yymmdd>-<nn>` |
| (v0.4) Triage puts work in the wrong module | The module is shown in the triage block before anything is created; it asks when two modules fit; folders are created only after that |
| (v0.4) Existing repos use the old `<area>/phases/<phase>/` layout | Scripts read both layouts; nothing is moved; new features in an old-layout area go into its `phases/` folder until the user chooses to migrate |
| (v0.4b) Detection guesses a surface wrong and the wrong roles or evidence follow | The proposal is confirmed by the user on first run and stored in `project.md`; triage shows surfaces and roles before work starts; a surface can be edited any time |
| (v0.4b) A stack's test runner has no name filter, so AC-tagged tests can't be run alone | The generic adapter runs the whole suite and parses results for the AC IDs; the gate still fails when an ID has no passing test |
| (v0.4b) Mobile and AI evidence can't run in evals or on a CI box without tools | The runner records "not run" with the exact reason; signoff needs an explicit waiver; the fixture tests cover the adapter logic without the devices |
| (v0.4b) The agent bodies grow and quality drops elsewhere | Surface sections are short tables, loaded for the feature's surfaces only; every existing eval must hold |
