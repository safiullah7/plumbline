# Plumbline v0.4 dev plan: adaptive delivery for any kind of software

Status: DRAFT (revision 2), awaiting Safi's approval
Owner: Safi
Written: 2026-10-24, from the v0.3 release, the agent audit of 2026-10-24 and the
Claude Code docs. **Revision 2** applies an independent break-test of revision 1
against the code (see §13). Supersedes the Release 4 summary in
`docs/dev-plan.md`, which points here.

How to read this: §1–5 say what and why, §6 is the exact specification (formats,
interfaces, rules), §7 the step-by-step build order, §8 the tests, §9 the
definition of done. Nothing in §6–9 is optional unless marked so.

---

## 1. Purpose

After v0.4, this is true:

1. **One command starts any work:** `/plumbline:build <request>`.
2. **The plugin sizes the work** (Quick, Standard, Full) and **knows what kind of
   software it touches** (its surfaces: web, mobile, API, CLI, library, data, AI,
   infra). From those it **chooses the roles, the evidence, the docs and
   team-or-subagents** itself. It asks the user only when something is genuinely
   unclear, and always shows its decision before starting.
3. **A bug fix costs a bug fix:** product → lead → one engineer → reviewer, with
   no team, no design phase and no document folder.
4. **Docs are organised by module and feature,** and old projects keep working.
5. **Every role adapts to the surface:** QA produces the right evidence (emulator
   screenshots, API transcripts, eval sets), UX takes part only for UI, the
   reviewer checks what matters for that kind of code, and the gates run the
   right test command per workstream.
6. **Quality bars hold at every size and surface:** observable criteria, tests
   named after them, evidence that fits, a review, a PR the user merges; the
   eval suite proves no case regressed.

## 2. Scope

**In:**
- adaptive sizing and the `/plumbline:build` entry point;
- module and feature docs layout with repo-wide feature numbering;
- project profile, surface detection and confirmation;
- roles, evidence, templates and review checklists by surface;
- test-gate adapters for Node, Python and Go, plus a generic adapter;
- the text-presence improvement to the visual comparison (optional, last).

**Out (later releases):**
- dedicated adapters for Rust, .NET, Gradle/Android, Flutter and Swift: these
  use the generic adapter, with documented recipes, until they can be tested on a
  machine with those toolchains;
- a mobile capture script (the QA runner gets verified commands instead);
- migrating old `phases/` layouts automatically;
- the team token benchmark.

## 3. Working rules (non-negotiable)

1. **Quality guard.** v0.3's eval results are the baseline. Any case that scores
   below its baseline after a change is fixed or the change is reverted before
   the PR. New cases are recorded.
2. **Deterministic gates.** Anything that decides pass/fail is a script (bash +
   jq, or Node built-ins), never model judgement.
3. **Nothing ships untested.** Hooks and scripts are covered by the self-tests,
   skills and agents by the evals, teams and git flows by the live smoke test.
   Code that can't be tested on Safi's machine doesn't ship as code (it becomes
   documented guidance).
4. **Two PRs, one release:** v0.4a (sizing + layout), then v0.4b (project
   awareness). Each gets its own evals and smoke test, then stops for review.
5. **Commits credit Safi only.** No co-author trailers, no generated-with
   footers.
6. **Helper files go in the scratchpad or `$TMPDIR`,** never in `D:\Repos`.
7. **Evals run with `--no-publish`, `--ablation none`, at most 2 runs in
   parallel** (RAM), Sonnet as judge, 3 runs per case for recorded results.
8. **Backward compatible.** Nothing a v0.3 user has on disk or in muscle memory
   stops working, including `/plumbline:kickoff <area> phase-NN`.

## 4. Verified constraints

| Fact | Consequence |
| --- | --- |
| Subagents can start subagents, up to 3 levels below the main conversation | The lead runs as a subagent and dispatches the engineer and reviewer; small work needs no agent team |
| `AskUserQuestion` is removed from every subagent | Every question to the user, including waiver approvals, is asked by the build skill in the main session |
| A dispatch can pass a `model` override | Triage runs on sonnet; judgement-heavy work keeps opus |
| Ownership and task hooks gate teammates; PreToolUse sees `agent_id` for any subagent | Subagent paths get the same checks from `ac-check.sh`, run by the lead, plus the reviewer; the waiver rule (§6.9) applies to every agent |
| Agent teams need `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` at startup | Team detection is "is the TeamCreate tool in my tool list", not an env var; Quick and Standard never need teams |
| Eval runs: no Bash on native Windows, no AskUserQuestion, no teams; graders see the main session's tool calls and files | Scripts are proven by self-tests; evals grade the main session's dispatches, the files written and the reply; git, PRs and nested dispatches are proven in the live smoke test |
| Skills can't read environment variables without a shell | Settings a skill must read live in a file (`project.md`), not env vars |
| `TaskCreated`/`TaskCompleted` hooks receive `task_subject`; the gates match `AC-[0-9]+-[0-9]+` | Quick criteria IDs keep that shape |
| v0.3 code facts relied on below: `md_table` matches headings by **prefix**; `qa-summary.sh` is the **only writer** of the Visual comparison and Accessibility sections; `signoff-check.sh` reads Accessibility columns 3–4 as counts and skips sign-off boxes with `phase pr\|merged`; `phase_dir` reads only line 1 of `.claude/current-phase`; the hooks self-test overrides `PLUMBLINE_TEST_AC` with a shell function | Every format in §6 respects them; §6.13 lists the exact column positions that must not move |

**To verify during implementation (not assumed):** each test runner's filter
and skip output (§6.8), the simulator/emulator commands in §6.10, and axe
injection under strict CSP. Each is checked against current docs and a fixture
before it's relied on.

## 5. Decisions already taken (Safi, 2026-10-24)

- One entry point `/plumbline:build`; three sizes; the plugin decides and asks
  only when unclear; a "always confirm" setting exists.
- Docs: one folder per module; a subfolder per Standard or Full feature; none
  for Quick.
- Browser tools stay optional; visual differences are for design review;
  accessibility blocks on serious and critical; no benchmark in this release.
- Surfaces cover any kind of software; web is one surface among others.

---

## 6. Specification

### 6.1 Sizes

| Size | Rule | Roles | Docs | Runs as |
| --- | --- | --- | --- | --- |
| **Quick** | All of: one module, ≤ 3 criteria, no new screen or flow, no schema change, no change to a contract another workstream depends on | Product (triage + criteria) → lead → 1 engineer → reviewer | None. Criteria, tests and review in the PR body; one row in the module's `changes.md` only if that folder already exists | Subagents only (main → lead → engineer and reviewer, depth 2) |
| **Standard** | Otherwise | Product, lead, 1–2 engineers, QA runner; UX only for UI surfaces with screen, flow or visible-copy changes | Feature subfolder in the module (slim profile); the module folder is created first if missing | Subagents; a team only if 2 engineers and the TeamCreate tool is available, else sequential subagents |
| **Full** | Any of: a new module, 3+ screens, a data migration, an auth/permissions model change, billing, cross-module work, ~10+ criteria | Everyone the surfaces need | New module folder + feature subfolder, or a feature subfolder in an existing module (full profile) | Agent team with all gates |

**Escalation:** if Quick or Standard work grows past its rule, the lead stops and
re-triages. It never quietly expands the scope.

### 6.2 Docs layout

```
docs/product/
  project.md                       project profile (§6.3), one per repo (v0.4b)
  <module>/
    vision.md                      who it's for, problem, principles, "## Features" table
    design-principles.md           only when the module has a UI surface
    tokens.css                     web-ui only, created by the UX engineer
    decisions.md
    changes.md                     one row per Quick change: | Date | Request | ACs | PR |
    <nn>-<feature-slug>/
      .plumbline                   feature metadata (§6.2.1); written by kickoff.sh only
      spec.md  acceptance-criteria.md  dev-plan.md  questions.md  progress.md
      test-plan.md  qa-report.md  signoff.md  [ux.md]
      contracts/  [prototypes/]  briefs/  qa/
```

- `<nn>` is a **repo-wide sequence**. `next_feature_number()` scans
  `docs/product/*/[0-9][0-9]*-*/` and legacy `docs/product/*/phases/phase-[0-9]*/`,
  takes the highest number and adds 1, zero-padded to at least two digits. AC IDs
  are `AC-<nn>-<nnn>`.
- `.claude/current-phase` line 1 holds the active feature folder (unchanged).
- **Legacy layout:** `docs/product/<area>/phases/<phase>/` keeps working.
  - `module_dir()` returns the feature folder's parent, or its grandparent when
    the parent is named `phases`.
  - A legacy feature without `.plumbline` reads as `profile=full`, surfaces from
    `project.md` (or `web-ui` if there's none), `ux=yes`.
  - New features in a legacy area go into its `phases/` folder with the next
    repo-wide number.
  - `/plumbline:kickoff <area> phase-NN` keeps its v0.3 behaviour exactly.
- **Wording:** "feature" replaces "phase" in docs and user-facing text; command
  names stay. Every regex that matched "phase" text is updated to accept both
  (§6.13).

#### 6.2.1 Feature metadata: `<feature>/.plumbline`

Agents rewrite `dev-plan.md` wholesale, so metadata lives in its own file, in
`key=value` form, one per line:

```
module=rooms
number=07
profile=standard        # quick is never stored; standard | full
surfaces=api,web-ui     # v0.4b; absent in v0.4a
ux=yes
created=2026-10-24
```

- Written only by `kickoff.sh`, and readable with `feature_meta <key>` in
  `lib.sh`.
- The ownership guard refuses writes to `*/.plumbline` from any agent (any
  `agent_id`); only the main session or the script may change it.

#### 6.2.2 Quick marker: `.claude/plumbline-quick`

While a Quick change runs, the build skill writes `branch=…` and `ids=…` here
and deletes it when done (or when the user cancels). `context.sh` sees it and
injects "Quick change in progress: no feature folder; don't write phase docs"
instead of the active feature's context, so a stale feature never leaks into a
Quick change.

### 6.3 Project profile (v0.4b): `docs/product/project.md`

Created on first use, confirmed by the user, read by triage, the lead, the
gates and QA:

```markdown
# Project profile

Confirmed by: <user> on <date>. Edit it when the product changes shape.
Confirm: auto
Multi-tenant: no
Sensitive data: none

## Surfaces
| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |
| --- | --- | --- | --- | --- | --- | --- |
| web-ui | Next.js | apps/web/** | npm run dev -w apps/web (http://localhost:3000) | npm run -s typecheck -w apps/web | npm run -s lint -w apps/web | node --dir apps/web |
| api | Go | services/api/** | go run ./cmd/api (http://localhost:8080) | go vet ./... | golangci-lint run | go --dir services/api |
```

- **`Confirm:`** is `auto` (decide and ask only when unclear) or `always`
  (confirm every triage). It replaces the env var, which skills can't read.
- **`Multi-tenant:` and `Sensitive data:`** are read by the agents (reviewer,
  product), not by scripts.
- **Surfaces:** `web-ui`, `mobile-ui`, `desktop-ui`, `api`, `service`, `cli`,
  `library`, `data`, `ai`, `infra`.
- **`AC tests`:** an adapter name with arguments (§6.8), or `generic` with the
  command in a fenced block under `## Generic commands`. Cells never contain
  `|`, because `md_table` splits on it.
- **Paths** are space-separated globs, as in the Ownership table.

**Detection** (`detect-project.sh`, proposal only):
1. **Find package groups:** the root, plus every directory with a manifest
   (`package.json` workspaces, `pnpm-workspace.yaml`, `go.work`, Cargo
   workspace members, nested `pyproject.toml`, `pubspec.yaml`). Skip
   `node_modules`, `.git`, `vendor`, `dist`, `build`, `target`, `.venv`.
2. **For each group, apply every signal** (not "first match wins"), so one
   group can propose several surfaces:

   | # | Signal | Proposed |
   | --- | --- | --- |
   | 1 | `package.json` deps include next, react, vue, svelte, angular, solid | web-ui (Node) |
   | 2 | `package.json` deps include express, fastify, @nestjs/core, hono, koa | api (Node) |
   | 3 | `pyproject.toml`/`requirements*.txt` include fastapi, flask, django | api (Python); otherwise `[project.scripts]` → cli; else library |
   | 4 | `go.mod` plus `cmd/`; net/http or a known router imported → api, else cli | api or cli (Go) |
   | 5 | `pubspec.yaml` with a `flutter:` SDK dependency | mobile-ui (Flutter) |
   | 6 | `Cargo.toml` `[[bin]]` → cli, `[lib]` only → library | cli or library (Rust) |

3. **Hints, proposed as "(check)" rows the user must keep or delete:**
   - LLM SDK dependencies (anthropic, openai, langchain, llama-index) → ai;
   - `dbt_project.yml` or a `dags/` folder → data;
   - root `*.tf`, `helm/` or `k8s/` → infra;
   - an iOS or Android app folder with no Flutter → mobile-ui;
   - Electron or Tauri → desktop-ui.

   `.github/workflows` and migration `*.sql` files are never signals.
4. **Commands** are proposed only when the script exists in that package. The
   package manager comes from the lockfile (`npm -w`, `pnpm --filter`,
   `yarn workspace`). Unknown cells are left blank for the user.
5. **Output:** `detect-project.sh` prints the proposal; `--write` writes it only
   if `project.md` doesn't exist. The build or kickoff skill shows the proposal
   and asks the user to confirm or edit before writing.

### 6.4 Roles and evidence by surface (v0.4b)

**Evidence kinds** are fixed tokens, so scripts can check them: `screenshots`,
`axe`, `journeys`, `checklist`, `flow-tests`, `contract`, `authz`, `negative`,
`transcripts`, `job-tests`, `failure-cases`, `golden-output`, `doc-examples`,
`api-diff`, `sample-run`, `idempotency`, `eval-set`, `injection`, `plan-output`.

| Surface | UX engineer | Required evidence kinds | Reviewer adds | Accessibility at signoff |
| --- | --- | --- | --- | --- |
| web-ui | Yes | screenshots, axe, journeys | UI states, keyboard, contrast, XSS | axe rows or a waiver |
| mobile-ui | Yes, device-size mockups, platform conventions | screenshots, flow-tests, checklist | Offline/flaky network, permissions, lifecycle, battery, store rules | checklist rows or a waiver |
| desktop-ui | Yes | screenshots, checklist | Window states, keyboard, updates | checklist rows or a waiver |
| api | No (the lead reviews API design) | contract, authz, negative, transcripts | Authorization on every endpoint, validation, idempotency, migrations; tenant scoping when `Multi-tenant: yes` | exempt |
| service | No | job-tests, failure-cases | Idempotency, retries, dead letters, observability | exempt |
| cli | Light: product specifies help, flags, exit codes | golden-output | Exit codes, stdout/stderr, `--help`, no prompts in non-interactive paths | exempt |
| library | No | doc-examples, api-diff | Breaking changes, naming, error types | exempt |
| data | No | sample-run, idempotency | PII, backfills, partial failure | exempt |
| ai | Only with a conversational UI | eval-set, injection | Prompt injection, data leakage, eval coverage, fallbacks, cost | exempt (UI rules apply to its UI) |
| infra | No | plan-output | Blast radius, secrets, rollback | exempt |

- **Multi-surface features** take the union of required kinds.
- **Recording:** the QA runner records evidence in qa-report.md's
  `## Evidence` table (§6.7). `signoff-check.sh` requires each kind for each of
  the feature's surfaces, with Result `pass`, unless a waiver line exists (§6.9).

### 6.5 Triage: rules, block and questions

**Order of decisions:** module → size → (v0.4b: surfaces) → UX → engineers →
docs → team.

- **Module:** match the request against `docs/product/*/` names and the code
  layout. Answer `existing` or `new (<name>)`. Ask when two modules fit, or when
  it's unclear whether it's new.
- **Size:** the rules in §6.1. Ask when it can't decide between two sizes.
- **Surfaces (v0.4b):** the profile surfaces whose Paths the change touches.
  Ask when none fits.
- **UX:**
  - v0.4a: yes if and only if a screen, flow or visible copy changes (beyond a
    label);
  - v0.4b: additionally, only when a UI surface is touched.
- **Engineers:** one per independent file area, max 4; Quick is always 1.
- **Docs:** by §6.1–6.2.
- **Team:** Full → yes; Standard → yes only with 2 engineers and TeamCreate
  available; Quick → no.

**Ask the user only when:**
- the request is too vague for observable criteria;
- the size or the module is undecidable;
- the size is Full (confirm the commitment, and that teams are on);
- (v0.4b) there's no `project.md` yet (confirm the detected profile);
- `Confirm: always` is set.

**Fixed block, printed verbatim.** The lines marked (b) arrive in v0.4b; the
evals grade each line with a regex.

```
Plumbline triage
Size: Quick | Standard | Full
Module: <name> (existing | new)
Folder: none | docs/product/<module>/<nn>-<feature-slug>/
Surfaces: <comma-separated>                                  (b)
Roles: <e.g. product, lead, 2 engineers, UX, QA runner>      (b)
Evidence: <kinds per surface, e.g. api: contract, authz>     (b)
UX: yes | no
Engineers: <n>
Docs: none | slim | full
Team: no | yes
Why: <one line>
```

**Quick criteria IDs** are `AC-<yymmdd>-<nn>` (e.g. `AC-261024-01`): unique
per day, and matching the gate regex and test naming.

### 6.6 Flows

**Quick**
1. **Preflight (build skill, main session).**
   1. Check the working tree is clean. If not, ask: stash, continue on top, or
      stop.
   2. Check the user's permissions cover the commands the lead and engineer
      will run (`git checkout -b`, `git add`, `git commit`, `git push`,
      `gh pr create`, and the surface's test commands). If any would prompt or
      be denied, ask once to approve them for this change, or stop with the
      list.
2. **Triage.** The product engineer subagent (triage mode, `model: sonnet`)
   returns the block and 1–3 criteria. The build skill prints the block and
   asks only per §6.5.
3. **Marker.** The build skill writes `.claude/plumbline-quick`.
4. **Lead subagent, quick mode:**
   1. create `quick/<yymmdd>-<slug>` from the default branch's latest commit;
   2. dispatch one senior engineer subagent with the criteria and conventions
      (test-first; the engineer commits its files by path);
   3. run `ac-check.sh "<IDs>"`;
   4. dispatch the code reviewer (sonnet) with the diff and criteria;
   5. have Critical findings fixed by the engineer, then re-check;
   6. push, then open the PR with `gh pr create` (request, criteria, tests and
      review in the body). Without `gh` or authentication, push and print the
      compare URL;
   7. add the `changes.md` row if the module folder exists.

   It never creates a folder or merges. If the work grows past Quick, it
   re-triages.
5. **Wrap-up.** The build skill deletes the marker and reports the PR (or the
   compare URL) and the check results.

**Standard**
1. `kickoff.sh <module> <slug> --profile standard [--ux|--no-ux]
   [--surfaces a,b]` creates the folder, writes `.plumbline` and sets the
   current feature.
2. Product (subagent) writes the slim spec and criteria. UX (subagent) writes
   `ux.md` and one mockup per key screen, only if UX is in the roles.
3. Lead (subagent) writes `dev-plan.md` with a `Surface` column per teammate
   (v0.4b). The build skill asks the user to approve the plan (one question).
   The lead then sets READY and runs `make-briefs.sh`.
4. Build: 1–2 engineers, as subagents dispatched by the lead or as a team when
   available. Each runs `ac-check.sh` and gets a reviewer per workstream.
5. QA runner (subagent) produces the Evidence table and runs `qa-summary.sh`,
   then `signoff-check.sh`, then the PR.

**Full**
1. `kickoff.sh <module> <slug> --profile full [--new-module] [--surfaces …]`.
   With `--new-module` the module docs are created and the product engineer
   writes the module vision first.
2. Then today's flow, with roles from §6.4: discover → spec, UX, test plan →
   plan → user approval → team build → QA → signoff.
3. If TeamCreate isn't available, it stops and prints the launch command.

**Waivers (any size):** only the build skill writes a waiver line, after asking
the user in the main session (§6.9).

### 6.7 Files and formats

| File | Section | Format (column order is fixed) | Writer |
| --- | --- | --- | --- |
| qa-report.md | `## Accessibility` | `\| Screen \| Width \| Critical \| Serious \| Moderate \| Minor \| Report \| Method \|`; Method = `axe` or `checklist` | `qa-summary.sh` only |
| `qa/a11y/*.json` | — | axe results (one object or an array) | `capture.mjs`, or QA's own tests |
| `qa/a11y-checklist.tsv` | — | `screen<TAB>width<TAB>check<TAB>result(pass\|fail)<TAB>impact(critical\|serious\|moderate\|minor)<TAB>evidence` | QA runner (mobile, desktop) |
| qa-report.md | `## Evidence` | `\| Kind \| Surface \| Location \| Result \|`; Kind from §6.4 tokens, Result `pass`, `fail` or `not run` | QA runner |
| qa-report.md | anywhere | `Evidence waived: <kind> (<surface>) - <reason> (approved by <name>)` and `Accessibility waived: <reason> (approved by <name>)`; dash may be `-`, `—` or `:` | build skill only (§6.9) |
| module `changes.md` | table | `\| Date \| Request \| ACs \| PR \|` | lead (Quick) |
| module `vision.md` | `## Features` (legacy `## Phases`) | `\| Feature \| Goal \| Outcome \| Why next \| Status \|` | product |

- `qa-summary.sh` builds Accessibility rows from both sources, adding up
  checklist failures by impact into the count columns.
- `signoff-check.sh` keeps reading columns 3 and 4 as counts; column 8 is
  informational.
- qa-report.md must not contain any other heading starting with
  `## Accessibility` or `## Evidence` (prefix matching).

### 6.8 Scripts and interfaces

| Script | Interface | Exit | Notes |
| --- | --- | --- | --- |
| `kickoff.sh` | Module form: `kickoff.sh <module> <feature-slug> [--profile standard\|full] [--ux\|--no-ux] [--new-module] [--surfaces s1,s2]`. Legacy form: `kickoff.sh <area> phase-NN` | 0 ok; 1 usage; 2 `--new-module` on an existing module | Module docs if missing (always with `--new-module`); folder `<nn>-<slug>`; profile and surface overlays; placeholders (`<phase>`→nn, `<Module>`, `<module>`); writes `.plumbline` and `.claude/current-phase`; prints the folder |
| `ac-check.sh` | `ac-check.sh "<IDs>" [--surface <s>]` | 0 pass; 1 a check failed (last 30 log lines on stderr); 2 usage | Calls `run_checks` |
| `run_checks` (lib.sh) | `run_checks "<IDs>" [surface]` | 0 or 1 | **Precedence:** `PLUMBLINE_TYPECHECK`/`LINT`/`TEST_AC` env vars > the surface's `project.md` commands and adapter > legacy `npm run -s …` defaults. The task gate maps a failure to exit 2 |
| `ac-tests/node.sh`, `pytest.sh`, `go.sh` | `<adapter>.sh "<IDs>" [--dir <path>]` | 0 only if every ID has ≥ 1 passing test and none failing or skipped-as-pass; 1 otherwise | Prints `AC-01-001: pass (2)` / `fail` / `missing` lines; strips `\r` |
| `ac-tests/generic.sh` | `generic.sh "<IDs>"`, command from `project.md` with `{ids_regex}` and `{ids_underscored}` placeholders | exit code of the command | Prints a warning that per-ID presence isn't proven |
| `detect-project.sh` | `detect-project.sh [--write]` | 0 | §6.3 |
| `lib.sh` additions | `feature_meta <key>`, `module_dir`, `next_feature_number`, `project_surfaces`, `surface_row <surface>`, `run_checks` | — | Read-only except `run_checks` |
| `phase-evidence.sh` | unchanged CLI | — | Uses `module_dir`; scans `[0-9][0-9]*-*/` and `phases/*/`; reads `## Features` or `## Phases` |
| `context.sh` | unchanged | — | Adds `Module:` (and `Surfaces:` in b); Quick marker handling (§6.2.2) |
| `signoff-check.sh` | unchanged CLI | — | §6.9 rules |
| `qa-summary.sh` | unchanged CLI | — | §6.7 Accessibility from both sources; Method column |
| `status.sh` | unchanged | — | `TEST_GLOBS` adds `*_test.go test_*.py *_test.py *_test.dart *Tests.swift *Tests.cs` |

**Adapter rules (verify flags against current docs, §4):**
- **node:**
  - choose the runner from `package.json` (vitest, jest, else node:test);
  - for node:test, use `--test-reporter=tap --test-name-pattern=<alternation>`;
    for jest and vitest, use `-t <alternation>` with the JSON reporter;
  - **skipped and todo tests never count as passes** (TAP `# SKIP`, `# TODO`;
    JSON status `skipped`/`pending`).
- **pytest:**
  - run `python -m pytest -k "<ids in AC_01_001 form joined by or>" -rA -q`;
  - `PASSED`/`FAILED` lines count, `SKIPPED` and `XFAIL` don't;
  - match `AC-01-001` and `ac_01_001`, case-insensitively.
- **go:**
  - run `go test ./... -run 'AC[-_]01[-_]001|…' -v`;
  - count `--- PASS:`, `--- FAIL:` and `--- SKIP:` lines whose name contains
    the ID in either form;
  - ignore parent tests that only wrap subtests.
- **IDs in identifiers:** where a language can't use dashes (Go functions,
  Python, Rust), `AC_01_001` and lowercase forms are accepted everywhere.

### 6.9 Signoff rules and waivers

**Gaps, in addition to v0.3:**
1. **Evidence (v0.4b):** for each surface in `.plumbline`, each required kind
   from §6.4 needs an Evidence row with Result `pass`, or a matching
   `Evidence waived:` line. Features without `surfaces=` (legacy or v0.4a) skip
   this rule.
2. **Accessibility:** applies only when the feature has a UI surface (legacy and
   v0.4a features: whenever ux.md has a `## Screen inventory` with rows, as in
   v0.3).
   - Any row with Critical or Serious above 0, or a non-number in those
     columns, is a gap.
   - No rows at all is a gap unless an `Accessibility waived:` line exists.
3. **Sign-off boxes:** skip lines matching `(phase|feature) pr|merged`.

**Waivers can't be self-approved.** The ownership guard refuses any Edit or
Write from an agent (any `agent_id`, teammate or subagent) whose new content
contains `Evidence waived:` or `Accessibility waived:`. It answers "Only the
user can approve a waiver. Tell the lead which evidence is missing and why." The
build skill asks the user with AskUserQuestion and writes the line itself in the
main session.

### 6.10 Mobile capture (guidance in the QA runner; v0.4b)

Commands are verified against current docs before shipping:
- **iOS:** `xcrun simctl io booted screenshot <file>`.
- **Android:** `adb exec-out screencap -p > <file>` (binary-safe on Windows:
  use `adb exec-out` with no shell redirection, writing via PowerShell or bash
  as documented).
- **Flow tools when present:** Maestro (`maestro test <flow.yaml>` with
  `takeScreenshot`), `flutter test integration_test`, Detox, XCUITest,
  Espresso.
- **Mockups** are captured at the same device size so `visual-diff.mjs`
  compares like with like; a size mismatch is reported, never cropped.
- **No device:** the runner records `screenshots` as `not run` with the boot
  command, and asks the lead for a waiver.

### 6.11 Templates

| Template | Change | When |
| --- | --- | --- |
| `templates/module/` (copy of `area/` plus changes; `area/` kept for the legacy form) | `vision.md` with `## Features`; `design-principles.md`; `decisions.md`; `changes.md` | a |
| `templates/standard/` overlay | slim `spec.md` (Goal, Requirements P0/P1, Business rules, Data and permissions, Non-Goals, Success metrics); `test-plan.md` with Traceability (Status in column 4) and Evidence; `signoff.md` without "Design verification" when there's no UX | a |
| `templates/phase/signoff.md` | box "Feature PR opened" (the regex accepts both) | a |
| `templates/phase/qa-report.md` | `## Accessibility` gains Method; `## Evidence` table | a (Method), b (Evidence) |
| `templates/project.md` | §6.3 | b |
| `templates/surface/mobile/` | `ux.md` keeping `## Screen inventory`, device sizes 390×844 and 430×932, platform conventions, gestures, offline states; checklist guidance | b |
| `templates/surface/api/` | `contracts/README.md` (schema location, versioning); test-plan Evidence rows | b |
| `templates/surface/ai/` | spec section "Model, prompts and limits"; test-plan section "Eval set" (location, size, threshold, golden set, injection cases, budgets) | b |
| `templates/surface/cli/` | spec section "Command surface" (commands, flags, exit codes, output formats, `--help`) | b |

### 6.12 Agents

| Agent | v0.4a | v0.4b |
| --- | --- | --- |
| product-engineer | Triage mode (§6.5) with the block, the ask rules, the "can't write observable criteria → say what's missing" rule; module language; Success metrics results | Reads `project.md`; surfaces and roles in triage; verification by the surface's evidence; generic examples |
| lead-engineer | Quick mode (§6.6); Standard sizing; keep product, design, qa and qa-runner rows; the scripts path; generic examples | `Surface` per teammate; HIGH-risk list by surface |
| senior-engineer | Works from criteria in the dispatch when there's no brief; commits by path in Quick; spawns research subagents only when running as a Full-size teammate (depth limit) | AC naming per stack (§6.8); short surface conventions table |
| ux-engineer | Module language | Only for UI surfaces; by surface: web (today), mobile (device-size mockups, platform conventions, checklist), desktop |
| qa-engineer | Evidence section in the test plan | Required kinds from §6.4 per surface; browser checks only for web-ui; eval sets for ai |
| qa-runner | Works without a brief; the Evidence table | Per-surface execution (§6.10), API transcripts, AI eval runs; never asks for a URL that doesn't exist; `not run` when a tool is missing; never writes waivers |
| code-reviewer | Unchanged checklist, generic examples | Base checklist plus surface rows; tenant isolation only when `Multi-tenant: yes` |

Each "By surface" section is a short table, at most 25 lines per agent.

### 6.13 Compatibility invariants (must not change)

- **Column positions:**
  - test-plan Traceability: Status in column 4;
  - qa-report Bugs: Severity in column 3, Status in 4, Summary in 5;
  - signoff Product findings: Status in column 4;
  - signoff Design findings: Severity in column 4, Status in 5;
  - questions: Status in column 6;
  - qa-report Accessibility: Critical and Serious in columns 3–4;
  - Ownership table: teammate in column 1, globs in column 2.
- **Headings:**
  - `## Ownership`, `## Team`, `## Tasks`, `## Contracts` in dev-plan;
  - `## Screen inventory` in every ux.md, mobile included;
  - `## Traceability`, `## Bugs`, `## Visual comparison`, `## Accessibility` in
    QA docs.
- **Idle gate:** the questions.md header is built from the folder name, so it
  reads `# 07-room-schedules questions` for the new layout and
  `# Phase 01 questions` for the legacy one.
- **`.claude/current-phase`:** line 1 is the folder.
- **Legacy CLI:** `/plumbline:kickoff <area> phase-NN` keeps working.

### 6.14 Optional: text presence in the visual comparison (PL-104)

A removed text column scores about 7% today and isn't flagged. The fix adds a
second signal:
- per block, "has ink" means the luma standard deviation is above a threshold;
- a block whose ink presence flips between prototype and app counts as
  different **only if at least 2 of its 8 neighbours also flip**, so a lone
  speck doesn't count;
- `different` becomes the share of content blocks that differ by either signal.

**Acceptance:**
- the missing-column fixture scores ≥ 20%;
- the speck and different-wording fixtures stay below 20%;
- identical images stay at 0%.

---

## 7. Step-by-step build order

Each step ends with its tests green before the next starts.

### Part A: v0.4a, sizing and layout (branch `v0.4a` from `main`)

| # | Step | Files | Done when |
| --- | --- | --- | --- |
| A1 | Baseline: copy `eval-v0.3.md` scores into the PR checklist | `docs/evals/` | Table in the PR draft |
| A2 | `lib.sh`: `feature_meta`, `module_dir`, `next_feature_number`, `run_checks` (moved from the task gate, with the §6.8 precedence) | `scripts/lib.sh`, `scripts/task-completed-gate.sh` | Hooks self-test 45/45 unchanged (it overrides `PLUMBLINE_TEST_AC`); new unit cases on both layouts |
| A3 | `ac-check.sh` | `scripts/ac-check.sh` | Self-test: pass, fail, no-test, usage; identical verdicts to the task gate on the same fixture |
| A4 | Compatibility fixes (§6.13): signoff box regex, idle-gate header, `phase-evidence.sh` on both layouts and both vision headings, `status.sh` globs | `scripts/*` | Self-tests for each on both layouts; all v0.3 self-tests still pass |
| A5 | Templates: `module/`, `standard/` overlay, signoff "Feature PR", qa-report Method column; `qa-summary.sh` writes Method | `templates/**`, `scripts/qa-summary.sh` | Self-test: Accessibility rows carry `axe`; signoff rule unchanged on columns 3–4 |
| A6 | `kickoff.sh` (module form and legacy form, numbering, overlays, `.plumbline`, current feature); `/plumbline:kickoff` calls it with a hand fallback for both forms | `scripts/kickoff.sh`, `skills/kickoff/SKILL.md` | Self-test: the legacy form reproduces v0.3's file set exactly; Standard into an existing module; Standard creating a missing module; Full new module; Full in an existing module; numbering continues across modules and legacy `phases/`; `--new-module` on an existing module exits 2 |
| A7 | Ownership guard: refuse `.plumbline` edits and waiver lines from agents; `context.sh`: `Module:` line and the Quick marker | `scripts/ownership-guard.sh`, `scripts/context.sh` | Hooks self-test: an agent writing a waiver is blocked, the main session isn't; `.plumbline` edits are blocked; the marker swaps the context |
| A8 | Agents (§6.12, a column) | `agents/*.md` | Review: no web-only text added; research subagents limited to Full teammates |
| A9 | `skills/build/SKILL.md`: preflight, triage dispatch, block, ask rules, marker, flows, team detection by tool list, waiver procedure, no-shell fallbacks | `skills/build/` | Read-through against §6.5–6.6 and §6.9 |
| A10 | Evals: the v0.4a cases in §8.2; rerun every case whose agent, skill or template changed | `evals/**` | New cases ≥ 2/3; every rerun ≥ v0.3 |
| A11 | README (sizes, `/plumbline:build` first, layout), `plugin.json` 0.4.0-alpha, `docs/dev-plan.md` progress | docs | Validation (`--strict`, `--profile directory`, marketplace) clean |
| A12 | Live smoke: v0.3 rows plus (a) a Quick task through `/plumbline:build` on a fixture repo: branch, test, `ac-check`, reviewer, PR or compare URL, no team, no folder; (b) a Standard kickoff into a module; (c) an agent's waiver write blocked. Token report of (a) | `tests/smoke/*`, `docs/evals/tokens-v0.4.md` | All rows PASS live; numbers recorded |
| A13 | PR "Plumbline v0.4a", then stop for review | — | Merged by Safi |

### Part B: v0.4b, project awareness (branch `v0.4b` from `main` after A13)

| # | Step | Files | Done when |
| --- | --- | --- | --- |
| B1 | `templates/project.md`; `detect-project.sh`; `project_surfaces`, `surface_row` | `scripts/*`, templates | Self-test on six fixture repos: Node web; Node API + web monorepo (npm and pnpm workspaces); Go API; Go CLI; Python FastAPI; Flutter app. Plus negatives: a repo with `.github/workflows` and migration `.sql` isn't proposed infra or data; an LLM SDK dependency is proposed as `ai (check)`; `--write` never overwrites |
| B2 | Adapters `node`, `pytest`, `go`, `generic`; `run_checks` uses the profile per surface | `scripts/ac-tests/*` | Per adapter on a fixture: pass, fail, missing, **skipped-not-pass**, the `--dir` monorepo case, and the underscore ID form; the gate picks the right adapter in a two-surface fixture; env vars still override |
| B3 | Evidence table, `.plumbline` `surfaces=`, signoff rules by surface (§6.9), checklist rows in `qa-summary.sh`, surface template overlays | scripts, templates | Self-tests: an API feature with contract, authz, negative and transcripts passes and fails without authz; a mobile feature passes with checklist rows and no axe; a web feature with neither axe nor waiver blocks; a legacy feature behaves as in v0.3 |
| B4 | Triage block (b) lines and roles; the build skill dispatches by roles and asks to confirm the detected profile on first run | `agents/product-engineer.md`, `skills/build/` | Evals (B6) |
| B5 | Agents by surface (§6.12, b column); generic wording; reviewer tenant rule; QA runner mobile guidance (§6.10) verified against docs | `agents/*.md` | Review: each surface section ≤ 25 lines; no clinic, tenant or patient wording outside the multi-tenant rule and eval fixtures |
| B6 | Fixtures (Flutter, Go API, Python data, AI service, CLI) and the v0.4b cases in §8.2; rerun every changed case | `evals/**` | New cases ≥ 2/3; every rerun ≥ v0.4a |
| B7 | PL-104 text presence (optional; skip if B6 runs late) | `scripts/visual-diff.mjs`, `tests/visual-selftest.mjs` | §6.14 acceptance |
| B8 | README "Works with" and the evidence table; generic-adapter recipes for Rust, .NET, Gradle, Flutter, Swift (documented, not shipped as scripts); version 0.4.0 | README, `plugin.json` | Validation clean |
| B9 | Live smoke: v0.4a rows plus an API-only Quick task with an API fixture (contract and authz tests, no UX, no screenshots asked for) | `tests/smoke/*` | All rows PASS live |
| B10 | PR "Plumbline v0.4b", then stop for review | — | Merged by Safi |

---

## 8. Tests

### 8.1 Self-tests (deterministic, on every change)

- **`tests/hooks-selftest.sh`:**
  - the 45 v0.3 cases;
  - `Module:`/`Surfaces:` context lines and the Quick marker swap;
  - waiver and `.plumbline` writes blocked for agents and allowed for the main
    session;
  - `run_checks` parity with the gate, and env-var precedence.
- **`tests/scripts-selftest.sh`:**
  - the 66 v0.3 cases;
  - `kickoff.sh`, both forms, every placement, numbering;
  - `ac-check.sh`;
  - compatibility (§6.13) on both layouts;
  - `qa-summary.sh` Method and checklist rows;
  - signoff by surface and waivers;
  - `detect-project.sh` on the fixtures;
  - the adapters, where the toolchain is installed; otherwise skipped with a
    note naming the missing tool;
  - PL-104 image cases.
- **Validation:** `claude plugin validate --strict`, `--profile directory` and
  the marketplace check.

### 8.2 Evals (behaviour; graders limited to what eval runs can see)

**Fixture:** the clinic repo with a `rooms` module in the new layout. v0.4b
adds `project.md` (api + web-ui) and the B6 fixtures. Every case grades the
main session's reply, its dispatches and the files written. Nested dispatches,
git and PRs are proven in the live smoke instead.

| Case | Part | Graders |
| --- | --- | --- |
| triage-quick-backend-bug | a | regex on the reply: `Size: Quick`, `UX: no`, `Engineers: 1`, `Folder: none` |
| triage-standard-screen | a | `Size: Standard`, `Module: rooms \(existing\)`, `UX: yes`, `Folder: docs/product/rooms/\d\d-` |
| triage-full-new-module | a | `Size: Full`, `Module: .+ \(new\)`, `Engineers: [2-4]`, `Docs: full` |
| triage-new-module-standard | a | a feature for a module with no folder: `Size: Standard`, `Module: .+ \(new\)` |
| triage-asks-when-vague | a | an LLM judge on the reply (asks a clarifying question); `tool_used Agent input_match "lead-engineer\|senior-engineer" max 0` |
| build-quick-dispatches | a | `tool_used Agent input_match lead-engineer`; regex over created files for `AC-\d{6}-\d\d` in a test file; `file_exists docs/product/*/[0-9][0-9]-*/** exists: false` |
| kickoff-module-feature | a | the skill's hand fallback creates `docs/product/rooms/\d\d-<slug>/spec.md` and `.plumbline` (file graders) |
| kickoff-creates-phase (existing) | a | unchanged, ≥ 1.00 (the legacy form) |
| triage-surfaces-api-web | b | `Surfaces: .*api`, `Roles:` excludes UX for an API-only request |
| triage-mobile | b | Flutter fixture: `Surfaces: mobile-ui`, `UX: yes`, `Evidence: .*flow-tests`, no "browser" |
| qa-plan-mobile | b | test plan names screenshots from an emulator or simulator, flow tests and a checklist; no URL |
| qa-plan-api | b | Go fixture: contract, authz and negative cases and transcripts |
| qa-plan-ai | b | AI fixture: an eval-set section with a numeric threshold and injection cases |
| runner-mobile-no-device | b | Evidence row `screenshots … not run`; no waiver line written; LLM: reports the boot command |
| reviewer-api-authz | b | missing authorization is Critical |
| reviewer-cli-interactive | b | an interactive prompt in a non-interactive path is flagged |
| reviewer-single-tenant | b | no tenant findings with `Multi-tenant: no` |
| ux-mobile-mockups | b | device-size mockups and a checklist; no axe or `capture.mjs` |
| All v0.3 cases | a, b | ≥ their recorded scores |

### 8.3 Live checks (Safi launches; teams and git can't run in evals)

- **Smoke:** A12 and B9 rows.
- **Tokens:** `tests/tools/token-report.sh` on the Quick task, recorded in
  `docs/evals/tokens-v0.4.md`.

---

## 9. Definition of done

**v0.4a:**
- A1–A12 pass;
- every v0.3 case is ≥ its score, and the new cases are recorded;
- the live smoke passes, including the Quick task, the module kickoff and the
  waiver block;
- `docs/evals/eval-v0.4a.md` and `tokens-v0.4.md` exist;
- the PR is merged by Safi.

**v0.4b:**
- B1–B9 pass;
- every case is ≥ its v0.4a score;
- the detection fixtures and installed adapters pass;
- an API feature and a mobile feature sign off correctly in the self-tests;
- the live smoke passes;
- `docs/evals/eval-v0.4b.md` exists;
- the PR is merged by Safi.

**Release 0.4.0:**
- both PRs are merged;
- the README documents sizes, layout, surfaces and evidence;
- `docs/dev-plan.md` records v0.4 as built.

## 10. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Triage sizes work too small and skips UX or QA it needed | The block is shown first; the lead re-triages when work grows; boundary evals; `Confirm: always` |
| Subagent paths escape the hooks | `ac-check.sh` and the reviewer are mandatory in quick mode; the smoke proves they ran; the waiver and `.plumbline` rules cover subagents too |
| A permission prompt or deny rule stalls a subagent mid-change | The build skill's preflight asks once in the main session, or stops with the list before any change |
| Nested subagents hit the 3-level limit | Quick and Standard stay at depth 2; engineers spawn research subagents only as Full teammates |
| AC IDs collide across modules | Repo-wide feature numbers; dated Quick IDs |
| A stale active feature leaks into a Quick change | The Quick marker swaps the injected context |
| Detection proposes a wrong surface | The user confirms on first run; "(check)" rows for weak signals; the block shows surfaces; `project.md` is editable |
| A runner reports skipped tests as passes | Adapters exclude skip and todo states, with a self-test for each |
| Mobile and AI tools absent | Honest `not run`; waivers need the user; adapter logic is tested on fixtures without devices |
| Agents game waivers | The guard blocks waiver lines from every agent; only the main session, after asking the user, can write one |
| Agent bodies grow and quality drops | Surface sections ≤ 25 lines; every existing eval must hold |
| Old layouts or the legacy kickoff break | Both layouts read everywhere; the legacy form reproduces v0.3 exactly (self-test); nothing is moved |
| RAM pressure during evals | 2 runs in parallel; `--max-cost-usd` as a brake |

## 11. Rollback

- Each PR is independently revertible.
- v0.4a leaves v0.3 behaviour intact for anyone who keeps using
  `/plumbline:kickoff <area> phase-NN`.
- v0.4b's surface logic is off when `project.md` is absent (v0.4a behaviour),
  and legacy features skip the evidence rule.

## 12. Checklist

- [ ] Plan approved by Safi
- [ ] A1–A13 (v0.4a): evals, smoke, PR, merge
- [ ] B1–B10 (v0.4b): evals, smoke, PR, merge
- [ ] `docs/dev-plan.md` updated: v0.4 as built
- [ ] README reflects sizes, layout, surfaces, evidence
- [ ] One real-project feature run after 0.4.0, findings into the next plan

## 13. Revision 2: what the break-test changed

An independent review of revision 1 against the code found 9 blocking and 6
important issues. All are resolved above:

| # | Issue in revision 1 | Resolution |
| --- | --- | --- |
| 1 | Part A depended on Part B (surfaces in the block, ac-check via `project.md`) | The block and `run_checks` are defined per part; surface lines and profile commands arrive in v0.4b; v0.4a uses env vars and legacy defaults |
| 2 | Evals graded a `UX:` line the block no longer had | `UX:` is back in the block |
| 3 | Eval graders that need Bash, git or nested dispatches | Evals grade what runs can see; git, PRs, nested dispatches and `ac-check` move to the live smoke |
| 4 | "No dispatch" in the vague case contradicted the triage dispatch | Graded as no lead or engineer dispatch |
| 5 | Checklist accessibility had no data path; `qa-summary.sh` would wipe it | `qa/a11y-checklist.tsv` plus a Method column, both written by `qa-summary.sh` |
| 6 | Waivers were prose and self-approvable | Fixed evidence kinds; an Evidence table; the guard blocks waiver lines from every agent |
| 7 | Renaming "phase" broke three regexes and a header | Compatibility invariants (§6.13), fixed in step A4 |
| 8 | The kickoff eval would break with the new CLI | The legacy form is kept and self-tested to reproduce v0.3 |
| 9 | Profile stored in `dev-plan.md` would be lost on rewrites | `.plumbline` metadata file, writable only by `kickoff.sh` and the main session |
| 10 | `run_checks` precedence vs the self-test's env override | Env vars > profile > legacy defaults |
| 11 | Adapter flags, skipped-as-pass, Go/Rust naming, monorepo dirs | Three tested adapters with `--dir`, skip handling and underscore forms; others documented as generic recipes |
| 12 | Detection too eager (workflows, `.sql`, first match wins) | Package groups, every signal per group, six core signals, weak signals as "(check)" |
| 13 | Quick flow: permissions, branch base, no `gh`, who commits, stale context, depth | Preflight in the main session, branch from the default branch, compare URL fallback, the engineer commits, the Quick marker, research subagents only in Full |
| 14 | Skills can't read env vars without Bash | `Confirm:` in `project.md`; team detection by tool presence |
| 15 | Column positions and test globs | §6.13 invariants; `status.sh` globs extended |
