# Plumbline dev plan: v0.1.2 → v0.3

Status: READY (approved 2026-10-24; corrected after verification, see
"Corrections after verification")
Progress: v0.1.2 merged (PR #2). v0.2 built; evals 0.84 → 1.00 with no case
below baseline (docs/evals/eval-v0.2.md); team token benchmark pending.
Owner: Safi. Written 2026-10-23 from the plugin review and the live smoke test.

## Goals

1. Fix the two confirmed bugs (Temp-path bypass, invisible idle escalation).
2. Make every role work from a method, not just a brief: discovery for product,
   a design loop for UX, task-system features for the lead, a start routine for
   engineers, evidence-based QA.
3. Cut token use per phase by roughly half **without lowering output quality**.
4. Prove each release on a fresh repo with real teammates before tagging it.

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
3. v0.3 after v0.2 has been used on at least one real phase.

## Risks

| Risk | Mitigation |
| --- | --- |
| Token savings from briefs hide context an engineer needed | Briefs always link to the full docs; eval cases include one task that needs a non-cited AC |
| Teammate hook semantics change (experimental feature) | Every hook has a self-test; the smoke test is rerun on each Claude Code upgrade |
| `SessionStart` output too long and crowds context | Hard cap of 60 lines enforced in the script and the self-test |
| Splitting QA into two agents loses continuity | Both read/write the same `test-plan.md` and `qa-report.md`; the planner's cases are the runner's checklist |
| `agent_type`-based identity spoofable by a stray subagent name | Ownership guard already requires a row in the Ownership table; document it |
