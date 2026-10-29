# Plumbline v0.5 dev plan: security by attack plan

Status: DRAFT (revision 7), awaiting Safi's approval
Owner: Safi
Written: 2026-10-28, from `main` at e45c66e (v0.4b merged: lean roles).

Revision 7 (2026-10-29) is a cost-and-quality pass over revision 6b: signoff
**runs** the attack tests instead of reading a pasted result; the independent
attacker is **scoped** to the attack surface the lead names; the "three own
attacks" count gate goes; the lead plans from an **attack catalogue** per risk
signal and names the **shared attack fixtures**; a free, deterministic
**secrets check** joins the gates; and the plan says plainly which gates run
things and which only read claims (§14).

Revision 6b (2026-10-28) folded in an independent review of revision 6 against
the code (nine findings, all confirmed: §13). Revision 6 replaced revision 5
(1,128 lines: an Opus security engineer, a plan-review gate chain, hashes and
stale verdicts; four break-tests found 99 holes in it). It stays in git
history. Safi's direction on 2026-10-28 made the design smaller and cheaper:
**the lead plans the attacks, the engineer who writes the code writes them as
tests first, a reviewer checks the tests really attack, and a different
engineer attacks the finished feature only when the risk is high.** No new
agent type, no plan-review gates.

How to read this: §1–5 say what and why, §6 is the exact specification, §7 the
build order, §8 the tests, §9 the definition of done. Nothing in §6–9 is
optional unless marked so.

---

## 1. Purpose

After v0.5, this is true:

1. **The plugin decides how much security work a change needs.** The product
   engineer's triage block gets a line `Security: none | attacks | independent`,
   chosen from the request, the project profile, the size and the surfaces. It is
   printed before any work starts. The lead can raise it from its plan; only the
   user can lower it, in a line no agent can write.
2. **`attacks` (the floor for anything security-relevant).** The lead writes an
   **attack plan** in `dev-plan.md` from a catalogue of attacks per risk signal:
   concrete attacks, each with an ID (`SEC-03-001`), the surface it runs on and
   what must happen. The engineer who builds the feature writes each attack as a
   failing test first, then makes it pass, on shared fixtures the plan names.
   The reviewer (Sonnet; Opus for HIGH work, which the risky signals usually
   are) reads every attack test against its plan row and reports any that
   doesn't really attack, and any catalogue item the plan has no row for.
   **Signoff runs every `SEC-` test through `ac-check` and needs it to pass**,
   and scans the branch's diff for committed secrets.
3. **`independent` (high risk only).** After the build, a **different** Sonnet
   engineer attacks the attack surface the lead named: it runs the lead's
   attacks, tries the ones the plan missed, writes attack tests of its own and
   logs findings. The authors fix; the attacker re-runs. Signoff runs its tests
   too and needs no open Critical or High finding.
4. **Routine work pays nothing.** At `none`, no attack plan, no extra pass, no
   new file, no test run at signoff: the reviewer's existing security checklist
   is all there is.
5. **Quality bars hold:** the attacker never edits the code it attacks, no agent
   writes the user's lines, and every v0.4b eval case keeps its score.

**Where the cost goes** (beyond v0.4b):

| Level | Model cost | Other cost |
| --- | --- | --- |
| none | nothing | nothing |
| attacks | a few hundred Opus output tokens for the attack plan (the lead is already planning on Opus); the author's attack tests, written inside its workstream; a longer reviewer report in a dispatch that already happens | wall time: signoff runs a handful of tests and a grep |
| independent | one scoped Sonnet-high run; fix rounds only when it finds something | the same |

The DineFlow staff portal run (§8.3) measures the `independent` pass against
what it finds. If it finds nothing the Opus reviewer didn't, D5 is revisited.

## 2. Scope

**In:**
- the `Security:` triage line and rubric (§6.2);
- the attack catalogue, the attack plan in `dev-plan.md` with its `Attack
  surface:` and `Attack fixtures:` lines, and `security.md` per feature (§6.3,
  §6.5);
- `SEC-` IDs through the ID-matching scripts, the task gates, briefs and the
  adapters (§6.4);
- signoff rules that run the SEC tests and the secrets scan; the user-only
  waiver and risk-acceptance lines (§6.4);
- prompt changes for product, lead, senior engineer and code reviewer (§6.5);
- the flows: Standard, Full, Quick (§6.6);
- self-tests, evals, README.

**Out (later releases):**
- external scanners (SAST, DAST) and dependency audits (they are about
  dependencies, not the engineers' work; `npm audit` and friends are a
  one-line profile cell for a later release);
- a separate security agent type or an Opus attacker as a default;
- penetration tests of deployed environments;
- module-level threat models or a security section in `vision.md`;
- risk acceptance in Quick (a Quick change with an open Critical or High
  finding is fixed or re-triaged).

## 3. Working rules (carried from v0.4)

1. **Quality guard.** `docs/evals/eval-v0.4b.md` is the baseline. Any case that
   scores below it after a change is fixed or the change is reverted.
2. **Deterministic gates.** Pass/fail is decided by scripts (bash and jq):
   the level, the SEC results (by running the tests, not by reading a claim),
   the secrets scan, open findings, waivers.
3. **Nothing ships untested.** Scripts and hooks: self-tests on both layouts
   and both TMPDIR modes. Agents and skills: evals. The whole flow: a live run.
4. **One PR, branch `v0.5` from `main`,** evals on it, stop for review.
5. **Commits and PRs credit Safi only.** No co-author trailer, no footer.
6. **Helper files go in `$TMPDIR`,** never in `D:\Repos`.
7. **Evals run with `--no-publish`, `--ablation none`, 3 runs per case,** cheap
   cases first, one group at a time, concurrency by free RAM.
8. **Backward compatible.** A feature with no `security=` key and no
   `Security level:` line behaves exactly as in v0.4b: no new gaps, context,
   dispatches, refusals or test runs, the same templates and files.
9. **Agents never write the user's lines,** never edit permission settings, and
   are dispatched without a `name` unless the step spawns teammates.
10. **The lead is always Opus and never writes application code.** Engineers
    are Sonnet; the attacker is a Sonnet engineer.
11. **Fail closed where security is in play.** When a feature's level is not
    `none`, an unknown level token, a malformed row, a missing table, a surface
    the profile doesn't list or a test run that can't start is a gap. Where it
    is `none`, nothing new happens (rule 8).
12. **One mechanism per threat** (§6.8). A mechanism without a row there is
    dropped.
13. **Gates run things where they can; where a gate can only read a claim, §6.8
    says so and no ritual is built around it.** Omission is caught by scripts;
    forgery is caught by the lead's review and the independent pass, as it is
    for the QA verdict today.

## 4. Facts from the v0.4b code that shape this plan

| Fact | Consequence |
| --- | --- |
| The ID pattern `AC-[0-9]+-[0-9]+` is read in `ac-check.sh` (the ID list and the output filter), `ac-tests/combine.sh` (the normaliser and two result filters), `make-briefs.sh`, `task-completed-gate.sh` and `task-created-gate.sh`. The adapters build their runner filter from the numbers alone: `common.sh` splits `AC-a-b` into `a` and `b`, `pytest.sh` selects `ac_<a>_<b>`, `generic.sh` has its own parser and `AC` placeholders | A SEC ID would select the AC test with the same numbers, or come back "missing". Every one of these sites takes the prefix from the ID (`AC` or `SEC`), and a self-test proves `SEC-03-001` never selects `AC-03-001`'s test |
| `signoff-check.sh` and `status.sh` read documents and never run tests; `ac-check.sh "<IDs>" --surface <s>` runs the tests for the IDs with the surface's adapter and prints one line per ID | At `attacks` and above, `signoff-check.sh` runs `ac-check.sh` for the plan's SEC IDs, per surface, and gaps on any line that isn't `pass`. It is the one place signoff runs anything; at `none` it runs nothing. The pasted result line of revision 6b is gone |
| TaskCompleted fires only for teammates (the gate exits 0 without a teammate name); a Standard feature built by subagents has no task gate | The lead runs `ac-check` for each workstream's SEC IDs during its review (as it does for AC IDs); signoff runs them again as the gate |
| The guard checks waiver lines on every agent write to every file, before it knows whether a build is active, and its Bash check matches anywhere in the command | The new phrases are checked only for files named `security.md` (Write and Edit by path; Bash only when the command writes to `security.md`), with their own message. ADRs, threat models, SECURITY.md and commit messages are unaffected |
| The template Ownership rows `product` and `qa` are `docs/product/**` (`*` crosses `/`), and plain subagents skip the Ownership check | We can't claim only the lead writes `security.md`. SEC results can't be forged (they are run); `Checked`, severities and `Independent pass:` can, and rule 13 says what covers that |
| `md_table` treats a row after a blank line as a new header and splits on every `\|` | `security_rows` is its own parser: it requires the exact header, counts every `\|` line up to the next heading, and any line it can't read, or a row with the wrong cell count, is a gap |
| The guard blocks `Evidence waived:` and `Accessibility waived:` line-starts and writes to `.plumbline` and `project.md`; its Bash rules are best effort (the guard's own header says so) | The same style of lock for the two new lines in `security.md`; `.plumbline` is already locked. The Bash lock on `kickoff.sh --set-security` is best effort too, backed by the signoff rule that a raise must be recorded |
| `evidence_waived` accepts a line only when filled in (no `<placeholder>`, ends with `(approved by <name>)`) | The new lines reuse that rule through one shared helper |
| `kickoff.sh`: exit 1 is usage or "exists", 2 is `--new-module`; the legacy form copies every file in `templates/phase/`, has no `.plumbline` today, and `tests/kickoff-selftest.sh` asserts that | `security.md` lives in `templates/security/`, copied only by `--set-security` and `--security`; those exit 0 or 1 only; a legacy phase gets its first `.plumbline` only when a level above `none` is set |
| In Quick the lead pushes and opens the PR itself (`lead-engineer.md` Quick step 6, `build/SKILL.md`), and Quick IDs are `AC-<yymmdd>-<nn>` | The lead's Quick rule changes (no PR while a SEC test fails or a Critical or High finding is open); Quick SEC IDs are `SEC-<yymmdd>-<nn>` |
| The lead runs as a subagent and can't ask the user | A "Needs user" return to the build skill, which asks, writes the user's lines and re-dispatches the lead (the pattern for evidence waivers) |
| The code reviewer already checks authorization on every endpoint, injection, secrets in logs and tenant isolation (`code-reviewer.md`), is read-only, and HIGH workstreams get it on Opus (`lead-engineer.md`) | The security lens is a few more lines in a dispatch that already happens, not a new run; auth, billing and tenancy work is HIGH, so `independent` features get the Opus reviewer on their riskiest tasks without extra rules |
| The e2e adapter (`playwright.sh`) needs the app running; QA starts the surfaces' Run commands and the build skill lists them in preflight | Before signoff at `attacks` and above, the skill makes sure each surface's Run command is up (it usually still is from QA), because signoff runs the attack tests |
| `make-briefs.sh` keeps each engineer's tasks and the `## Screen descriptions` it needs | The brief gets the engineer's attack rows and the `Attack fixtures:` line the same way |
| Eval runs: no Bash on native Windows, no AskUserQuestion, no teams; graders see the trace's tool calls and the last message | Agent behaviour is graded from file writes and the report; ordering across agents is proven in the live run |
| Subagents nest three levels | Standard/Full: the lead (depth 1) dispatches the reviewer and the attacker (depth 2). Quick: the same, one level shallower |

## 5. Decisions

**Taken (Safi, 2026-10-28):**
- The lead plans how to break the feature; no separate security agent and no
  plan-review gate.
- The engineer who writes the code writes the lead's attacks as tests first.
- An independent attack pass exists only for high risk.

**Defaults to confirm or change at approval:**
- **D1 Three levels:** `none`, `attacks`, `independent`. `independent`
  includes `attacks`.
- **D2 Risk acceptance:** the user may accept an open Critical or High finding,
  or a secrets-scan hit, in a user-only line, never in Quick.
- **D3 Quick:** may carry `attacks` (inline in the lead's plan, no feature
  folder); `independent` is never Quick, triage sizes it Standard at least.
- **D4 Full** features get at least `attacks`.
- **D5 The independent attacker** is a fresh Sonnet senior engineer at high
  effort, **scoped to the `Attack surface:` the lead names**, dispatched by the
  lead after every workstream is accepted and before QA. An Opus reviewer
  (with the security lens) reads the diff for HIGH tasks, as it already does
  in lean roles.
- **D6 Rounds:** at most three attack-and-fix rounds; then the lead returns
  "Needs user" with the open rows and the build skill asks per row (fix again,
  accept the risk, or stop).
- **D7 Tenant-scoped reads:** a new endpoint, query or export that reads or
  changes records chosen by an ID or filter the caller supplies, on a
  tenant-scoped store, is `attacks` (not `independent`); so is a bug fix
  inside an existing security-sensitive path. `quick-review-loop` (a by-id
  room lookup) therefore carries `attacks`; `build-quick-dispatches` (a 409 on
  a duplicate name) stays `none`.
- **D8 Waivers:** the user may waive either part (`attacks` or `independent`) in
  a user-only line. A waiver removes only the part it names.
- **D9 Signoff runs the SEC tests** (through `ac-check`, per surface) rather
  than reading a recorded result. The cost is wall time; the self-tests cover
  the run with a stub adapter.
- **D10 Secrets scan** at `attacks` and above: the diff from the merge base
  with the default branch must add no private-key block, no live key with a
  known prefix (`AKIA…`, `sk_live_`, `ghp_`, `xoxb-`, `-----BEGIN … PRIVATE
  KEY-----`) and no `.env` file other than `.env.example`, `.env.sample` or
  `.env.template`. A hit is a signoff gap unless the user accepts it (D2).
  Narrow patterns on purpose: a generic `password=` grep is noise.

---

## 6. Specification

### 6.1 Levels

| Level | Meaning | Written as |
| --- | --- | --- |
| none | the reviewer's existing security checklist is enough | `none` |
| attacks | the lead's attack plan from the catalogue; the author's attack tests on shared fixtures; the reviewer's check of them; signoff runs every SEC test and the secrets scan | `attacks` |
| independent | `attacks`, plus a scoped independent attack pass by a different engineer; signoff runs its tests too and needs no open Critical or High finding | `independent` |

Scripts accept exactly these tokens on a line of their own (spaces and
backticks stripped; nothing else on the line; a reason goes on the next line).
Any other value is a gap.

The **recorded level** is the highest of the two sources: the `security=` key
in `.plumbline`, and the `Security level:` line in `dev-plan.md` (the lead's
raise). A feature with neither is `none`. The **required level** is the
recorded level minus any part the user has waived (§6.4).

### 6.2 Deciding the level

**Triage (product engineer, triage mode)** prints a line after `Roles:` and
`Evidence:`: `Security: none | attacks | independent`.

**Rubric** (about what changes, not what the code merely touches):

| Signal | Level |
| --- | --- |
| New or changed authentication, sessions, tokens, passwords, keys, OAuth | independent |
| New or changed authorization: roles, permissions, who may see or do what | independent |
| Tenant scoping changes: a new tenant-scoped store, a cross-tenant query or share, new tenant resolution (`Multi-tenant: yes` only) | independent |
| Money: billing, payments, refunds, credits, pricing rules | independent |
| `Sensitive data:` is not `none` and the change stores, shows, exports or logs it in a new way | independent |
| A new entry point taking unauthenticated or external input: public endpoint, webhook, upload, import, parser of untrusted files | independent |
| `ai` surface with tool use, user data in prompts, or output that drives actions | independent |
| `infra` surface touching secrets, networking, public exposure or deletes | independent |
| A new read-by-ID or list endpoint, query or export on a tenant-scoped store, following the existing pattern (D7) | attacks |
| A bug fix or small change inside an existing security-sensitive path with no design change | attacks |
| Full size with none of the above (D4) | attacks |
| Routine work that follows an existing pattern: validation like a 409, UI changes, copy, sorting, filters on data the page already shows, reports on data the caller already sees | none |

**Precedence:** a request that matches the `none` row's named examples is
`none`; otherwise the highest matching row wins. The signals that matched are
what the attack catalogue (§6.5) is read against.

**Rules:**
- `independent` is never Quick (D3).
- **The lead can raise, never lower,** and only on the rubric's signals as they
  appear in its plan. It adds `Security level: <level>` to `dev-plan.md` (reason
  on the next line) and reports the raise. The build skill runs
  `kickoff.sh --set-security <level>` when it sees one and acts on
  `security-check`'s answer, never on prose. A line that doesn't parse goes
  back to the lead.
- **The user can raise it** at the triage question and at the plan-approval
  question. **The user can lower it only by waiving** (D8).
- `Confirm: always` confirms the level with the triage block.

### 6.3 Files and formats

**`dev-plan.md` gains `## Attack plan`** (the lead writes it when the level is
`attacks` or above; absent at `none`):

```
## Attack plan
Signals: tenancy, authorization
Attack surface: backend/src/features/orders/** (GET /orders, GET /orders/:id, PATCH /orders/:id/status); frontend/src/pages/Orders*
Attack fixtures: backend/test/attack/fixtures.ts (second restaurant with one order; staff session for each restaurant; unauthenticated client) — built in task [AC-02-001 SEC-02-001]
Skipped: "write with another tenant's foreign key": orders have no client-supplied foreign keys in this feature

| SEC ID | Surface | Attack | Must happen | Checked |
| --- | --- | --- | --- | --- |
| SEC-02-001 | api | Staff of restaurant B calls GET /orders/<id of an order of restaurant A> with a valid session | 404, nothing from the order in the body | |
```

Rules:
- `Signals:` names the rubric rows that matched. `Attack surface:` lists the
  paths and routes, pages, jobs or modules the attacks target; the attacker is
  scoped to it. `Attack fixtures:` names the shared test helpers (a second
  tenant, an unauthenticated client, a forged or expired token, a hostile
  payload builder) and the task that builds them first, so each engineer reuses
  them instead of inventing its own. `Skipped:` names each catalogue item for a
  matched signal that has no row, with why, in one line each.
- One row per catalogue item that applies, plus any the lead sees in the plan;
  usually four to twelve rows. Each attack is a concrete request, input or
  action, never a topic ("check authz"). `Surface` is a row of
  `docs/product/project.md` (the one whose AC tests cell runs the test).
  `Checked` is empty until the lead's review, then `matches` or `mismatch:
  <what>` from the reviewer's lens. Cells contain no `|`.
- IDs are `SEC-<nn>-<nnn>`, `nn` the feature number as in `AC-<nn>-…` (Quick:
  `SEC-<yymmdd>-<nn>`, as its `AC-` IDs). Each task line lists the SEC IDs it
  must withstand in an `Attacks:` line, and the task subject carries them:
  `[AC-02-004 SEC-02-001] Order list API`. "Done when" includes those tests
  passing.
- At `attacks` or above the lead adds `docs/product/**/security.md` to its own
  Ownership row.

**`security.md`** (feature folder, from `templates/security/security.md`,
created by `kickoff.sh --set-security` or `--security` the first time the level
is `attacks` or above; never over an existing file):

```
# Phase <phase> security

Independent pass: not started

## Own attacks
| SEC ID | Surface | Attack | Must happen |
| --- | --- | --- | --- |

## Findings
| # | Severity | Finding | Status | Evidence |
| --- | --- | --- | --- | --- |
```

- **Own attacks:** written by the attacker, one row per attack of its own that
  it wrote as a test (IDs continue the plan's numbering; same rules as the
  attack plan). Signoff runs these IDs like the plan's.
- **Findings:** written by the attacker; no `|` in any cell. Severity:
  **critical** (another tenant's or user's data readable or writable, auth
  bypass, money wrong), **high** (personal data leaked, privilege escalation
  inside a tenant, injection with a shown effect), **medium** and **low**
  (reported, not blocking). Status: `open`, `fixed` (the owner says so),
  `verified` (the attacker re-ran the attack and it is blocked).
- **`Independent pass:`** is `not started`, `not needed` (level `attacks`) or
  `complete (round <n>)`, written by the attacker when its pass is done.

**Quick** has no feature folder: the lead's inline plan carries the attack
rows (with `Surface`) and its final report shows `ac-check`'s output for them
(§6.6).

**User-only lines** (the build skill writes them in `security.md`, only after
the user says so):
- `Security waived: <attacks|independent> - <reason> (approved by <name>)`
- `Risk accepted: #<n> <severity> <the finding text exactly as in the row> - <reason> (approved by <name>)`
  (editing the row afterwards voids the acceptance);
- `Risk accepted: secret <path> - <reason> (approved by <name>)` for a
  secrets-scan hit (D10).

### 6.4 Gates and locks

1. **IDs.** Every site in §4 row 1 takes the prefix from the ID: the ID list and
   output filter in `ac-check.sh`; the normaliser and the two result filters in
   `combine.sh`; the runner-filter builder in `common.sh` (it keeps the prefix
   instead of dropping it); `pytest.sh` (`sec_<a>_<b>` for a SEC ID, `ac_<a>_<b>`
   for an AC ID); `generic.sh` (its parser and its `AC` placeholders); and the
   task gates and `make-briefs.sh`. Output prints the ID as given
   (`SEC-02-001: pass (1)`). A SEC-only task subject is accepted. `status.sh`
   keeps counting `AC-`. `AC-` behaviour is byte-identical.
2. **`kickoff.sh --security <level>`** (module creation) and
   **`--set-security <level>`** (an existing feature or legacy phase): write
   `security=<level>` into `.plumbline` (ensuring a trailing newline first),
   create `security.md` when the level is `attacks` or above, and never
   overwrite it. `none` writes nothing (rule 8; `--set-security none` is a
   no-op). A raise is accepted, the same level is a no-op, lowering or an
   unknown token exits 1 with a message. `--set-security` takes no positional
   arguments, so it is handled before the positional parse. On a legacy phase
   it creates `.plumbline` (the first one) only for a level above `none`.
3. **`scripts/security-check.sh [--no-run]`** prints the recorded level, the
   required level, the attack plan's rows and `Checked` cells, the result of
   each SEC ID (by running `ac-check` per surface, unless `--no-run`), the
   secrets scan, the open Critical and High findings, the independent-pass
   state and every gap; exit 1 on any gap. The build skill and the lead call
   it. Its rules live in `lib.sh` (`security_gaps`), and `signoff-check.sh`
   calls the same function, so the two never disagree. `--no-run` exists for
   the parsing self-tests and for the lead's quick look; the signoff gate
   always runs.
4. **`signoff-check.sh`** adds `security_gaps` only when the recorded level is
   not `none` (rule 8); every row is read by `security_rows` (§4), so an
   unreadable line is a gap, not a silent drop:
   - `security.md` missing, an unknown level token, or a missing `## Own
     attacks` / `## Findings` heading → gap;
   - the lead's `Security level:` line is higher than `.plumbline security=` →
     gap `raise not recorded; run --set-security`;
   - **unless `attacks` is waived:** the `## Attack plan` exists with at least
     one row (an empty or missing plan is a gap); every row's `Checked` starts
     `matches` → else gap per row; then, for each surface named in the plan
     and in Own attacks, `ac-check.sh "<its SEC IDs>" --surface <s>` runs, and
     every ID must print `pass` → gap per ID with the adapter's line; a surface
     the profile doesn't list, an AC tests cell of `none` or blank, or a run
     that can't start → gap;
   - **secrets scan** (D10) over `git diff <merge-base> HEAD` plus untracked
     files the feature's commits added: each hit → gap `secret-looking <path>:<line>`
     unless a `Risk accepted: secret <path>` line covers that path;
   - **open findings:** a Critical or High row whose Status isn't `verified`
     and that no matching `Risk accepted: #<n>` line covers → gap per row;
   - **at `independent`, unless `independent` is waived:** `Independent pass:`
     is `complete (…)` → else gap (no count of own attacks: their quality is
     the attacker's job and the lead's review; their tests are run like the
     plan's);
   - waiver and acceptance lines count only when filled in (no `<…>`
     placeholder, ends `(approved by <name>)`); a finding acceptance must repeat
     the row's severity and text (whitespace and case folded).
5. **The guard** (`ownership-guard.sh`) refuses an agent's Write, Edit or Bash
   that adds a line starting `Security waived:` or `Risk accepted:` to a file
   named `security.md` (Bash: when the command writes to `security.md`), with its
   own message. Other files and commands are untouched, so the guard is
   byte-identical for every other path. It also refuses `kickoff.sh
   --set-security` and `--security` from agents (best effort, as the guard's
   other Bash rules are; the signoff rule on unrecorded raises backs it).
6. **Ownership.** Rule 8 keeps the dev-plan template as it is, so at `attacks`
   or above the lead adds `docs/product/**/security.md` to its own Ownership row
   (a prompt rule). The template rows `product` and `qa` already match it, and
   plain subagents are not held to the table, so the plan does not rely on
   Ownership to stop self-grading (rule 13, §6.8).
7. **`make-briefs.sh`** adds `## Attacks to withstand` to each brief: the
   `Attack fixtures:` line and the attack plan rows for the SEC IDs in that
   engineer's tasks. No section when it has none.
8. **`status.sh`** adds one line when the level is not `none`:
   `security: <level> · <n> planned attacks, <m> own · open high <k> · independent pass <state>`
   (read-only; it runs nothing).

### 6.5 Agents

All prompt changes are small additions in the existing files; none adds an
agent type.

**`product-engineer.md`** (triage mode): the block's `Security:` line and the
rubric of §6.2 in a compact table; `independent` makes the size at least
Standard; criteria are unchanged (attacks are not acceptance criteria).

**`lead-engineer.md`:**
- At `attacks` or above, write `## Attack plan` (§6.3) before the user approves
  the plan: read the **attack catalogue** below against the signals triage
  named (and any it missed, which is a raise), write one row per item that
  applies and a `Skipped:` line for each that doesn't; name the `Attack
  surface:` and the `Attack fixtures:` with the task that builds them first;
  add `Attacks:` lines to the tasks that build the attacked code.
- Review each workstream: run `ac-check` for its AC and SEC IDs (without a team
  nothing else runs them), and dispatch the reviewer told "Security lens"
  (Sonnet; Opus for HIGH tasks, as now). Copy its verdict into each row's
  `Checked` cell; a `mismatch` goes back to the author as a task, and a missing
  catalogue item the reviewer flags becomes a new row and task.
- At `independent`, after every workstream is accepted and before QA, dispatch
  one fresh `senior-engineer` (model sonnet, effort high, no name) with the
  attack brief (§6.6), scoped to the `Attack surface:`. Route each finding to
  the engineer who owns the code, ask the attacker to verify the fix, and stop
  after three rounds (D6) with a "Needs user" return listing the open rows.
- Quick: push and open the PR only when `ac-check` passes every SEC ID and no
  Critical or High finding is open; otherwise stop and report.
- Never writes code or the user's lines.

**Attack catalogue** (in the lead's prompt, about 40 lines; each item becomes
one row when it applies to the change):

| Signal | Attacks |
| --- | --- |
| Authentication, sessions | no credential; expired or revoked token; a token issued for another audience or app; a downgraded role claim; replay after logout; CSRF where cookies carry the session |
| Authorization, tenancy | read another tenant's record by its ID; list without the tenant filter (count or page leak); write with another tenant's foreign key; tenant or role taken from the body or query instead of the session; the admin path with a staff token; the same action across two tenants in one request |
| Public or external input | missing, null and wrong-type fields; oversize body and strings; injection in each free-text field (SQL, HTML, header newline, path); duplicate submit or replay; unknown fields silently accepted (mass assignment); unexpected content type |
| Money | zero or negative quantity; price or total supplied by the client; rounding at the boundary; double charge on retry; currency mismatch; a discount applied twice |
| Sensitive data | appears in logs, URLs, error bodies, analytics or a public page; served without the check the rest of the record has; exported or searchable beyond the tenant |
| `ai` | prompt injection through user data; a tool call with another user's or tenant's ID; model output acted on without validation; a refusal or timeout that leaves state half-written |
| `infra` | a secret in state, output or logs; a port, bucket or queue exposed publicly; a destructive step with no plan review |

**`senior-engineer.md`:**
- **Author mode** (the brief has `## Attacks to withstand`): build or reuse the
  `Attack fixtures:` the brief names (the task that owns them builds them
  first); for each SEC ID, write the attack as a test first (a hostile caller
  doing exactly what the row says, asserting the "Must happen"), see it fail,
  then make it pass. Put the SEC ID in the test title, never in a file name.
  Report each SEC test's first failing run.
- **Attack round** (the dispatch says "Attack round"): attack only the `Attack
  surface:` named; never edit the code under attack or the authors' tests. Run
  the plan's attacks (`ac-check` for their IDs), then try what the plan missed:
  the catalogue items it skipped, and what the code itself suggests (other
  callers, other tenants' IDs, missing and malformed input, replay, state out
  of order), each as a real request or action. Quality over count; three or
  more of your own is the norm. Write each as an attack test in your own file
  inside the surface's test folder (title starts with a new SEC ID), add an
  Own attacks row, and for each confirmed break a Findings row (severity per
  §6.3, the failing run as evidence, no `|` in cells). After the authors fix,
  re-run and mark `verified`. Finish by writing `Independent pass: complete
  (round <n>)` and report findings by severity. Do not soften a severity to
  make the pass easier; say so when you are unsure.

**`code-reviewer.md`:** when the dispatch says "Security lens", read each named
SEC test against its plan row and return a table `SEC ID | matches or mismatch
| note` (a test that can't fail, asserts a status only, or attacks something
else is a mismatch), and list any catalogue item for a named signal that the
plan has no row and no `Skipped:` line for; otherwise unchanged (the existing
checklist stays).

**`qa-engineer.md`:** unchanged. QA tests the final code after the attack round.

**`skills/build/SKILL.md`:** prints the `Security:` line in the triage block;
at the plan-approval question shows the level and the attack plan's row count
and `Attack surface:`, and says the user can raise the level or waive a part;
runs `--set-security` and `--security`; after the build, at `independent`, has
the lead run the attack round before QA; when the lead returns "Needs user" it
asks per open row, writes the `Security waived:` and `Risk accepted:` lines
only after the user says so (the same procedure as evidence waivers) and
re-dispatches the lead; at `attacks` and above, before `signoff-check`, makes
sure each surface's Run command is up (signoff runs the attack tests); in Quick
it relays a stopped PR. `skills/signoff/SKILL.md` says the same about the Run
commands and the rules; `skills/kickoff/SKILL.md` mentions the flag and file.

### 6.6 Flows

**Standard** (level from triage; the build skill creates the folder with
`kickoff.sh … --security <level>`):

1. Product writes spec, criteria and `ux.md` (as now).
2. The lead writes the dev plan **with the attack plan** (catalogue, surface,
   fixtures) and `Attacks:` lines.
3. One user approval (the level and the attack plan summary are shown; raise or
   waive here). READY, briefs.
4. Build: the fixtures task first; authors write unit, e2e and attack tests
   first. The lead reviews each workstream with `ac-check` and the reviewer's
   security lens, and fills `Checked`.
5. At `independent`: attack round (below), then the authors' fixes.
6. QA tests the flows; product verifies; the skill makes sure the apps are up;
   `signoff-check` runs the SEC tests and the secrets scan; PR.

**Full:** the same after discovery; at least `attacks` (D4).

**Attack round** (the lead dispatches the attacker with: the attack plan
section, the `Attack surface:` and `Attack fixtures:`, each workstream's summary
for that surface, the run commands from the profile, and "Attack round"):
1. Attacker runs the plan's attacks and its own; writes tests, Own attacks rows
   and findings.
2. Lead sends each open Critical or High finding to its owner; the owner fixes
   with a failing attack test first.
3. Attacker verifies; findings become `verified`. Repeat up to three rounds.
4. Open rows after round three: the lead returns "Needs user" with the rows;
   the build skill asks (fix again, `Risk accepted:` (D2) or stop), writes the
   user's lines and re-dispatches the lead.

**Quick** (`attacks` only): the lead's inline plan carries the attack rows
(`SEC-<yymmdd>-<nn>`, with `Surface`) and names the fixtures; the engineer
writes the attack tests first; the reviewer runs with the security lens; the
lead runs `ac-check` for them and its final report shows the output. The lead
pushes and opens the PR only if every ID passes. A Quick change that turns out
to need `independent` is stopped and re-triaged to Standard.

### 6.7 Scripts and interfaces (summary)

| Piece | Change |
| --- | --- |
| `ac-check.sh`, `ac-tests/{common,pytest,generic,combine}.sh`, task gates, `make-briefs.sh` | the prefix comes from the ID (`AC` or `SEC`) |
| `lib.sh` | `security_level`, `security_required`, `security_rows` (own table parser), `security_gaps` (all §6.4.4 rules, running `ac-check` unless told not to), `secrets_scan`; one shared "filled-in approved line" helper |
| `kickoff.sh` | `--security <level>`, `--set-security <level>`; `templates/security/security.md` |
| `security-check.sh` (new) | `security_gaps` as a report, `--no-run` for parsing only |
| `signoff-check.sh` | calls `security_gaps` when the level isn't `none` |
| `ownership-guard.sh` | `Security waived:` and `Risk accepted:` in `security.md` only, and the best-effort script lock |
| `make-briefs.sh`, `status.sh` | attack section with the fixtures line; one read-only status line |
| Templates | `templates/security/security.md` is new; `templates/phase/dev-plan.md` is unchanged (rule 8: the lead adds the Attack plan section and its Ownership path only when the level needs them) |

### 6.8 One mechanism per threat

| Threat | Mechanism |
| --- | --- |
| Security work skipped on a risky change | Triage rubric in the block; the lead's raise; `signoff-check` compares the recorded and required level |
| The lead's attacks never become tests, or don't pass | SEC IDs in task subjects (task gate with a team, the lead's `ac-check` without one); **signoff runs every SEC ID through `ac-check`**; an empty plan is a gap |
| A test that cannot fail | The reviewer's security lens reads each test against its row; `Checked` must be `matches` (a claim the lead writes: rule 13) |
| The plan misses the obvious attack | The catalogue per signal, with `Skipped:` lines for items left out; the reviewer flags missing items; the independent pass at `independent` |
| An agent writes a result without doing the work | SEC results: not possible, they are run. `Checked`, severities, `verified`, `Independent pass:`: the honest limit (rule 13); the lead's review and the independent pass cover it, as the lead and product cover the QA verdict today |
| Shared blind spots between author and plan | The independent pass, scoped to the attack surface, with its own tests run at signoff |
| The attacker "fixes" what it found | The attacker never edits attacked code; findings go to the owner |
| The attacker wanders or costs too much | `Attack surface:` scopes it; one round unless it finds something; the DineFlow run measures it |
| Attack fixtures duplicated or wrong | `Attack fixtures:` names them and the task that builds them first; briefs carry the line |
| A High finding ignored or its row rewritten | Signoff gap unless `verified` or a `Risk accepted:` line that repeats the row |
| A secret committed | The secrets scan at `attacks` and above; user-only acceptance per path |
| An agent lowers its own bar | Waivers and acceptances are user-only lines the guard blocks in `security.md`; levels only go up |
| Level drift | The lead's `Security level:` line without `--set-security` is a signoff gap |
| A malformed table hides a finding | `security_rows` counts lines against rows and gaps on any it can't read |

### 6.9 Compatibility invariants (must not change)

- A feature with no `security=` key and no `Security level:` line: no new gap,
  file, context line, status line, dispatch, refusal or test run at signoff.
- `AC-` IDs behave exactly as before in every script; `status.sh` coverage is
  `AC-` only.
- The existing waiver lines and their locks, the lean-roles flow, the evidence
  rules and the adapters' output for `AC-` IDs are unchanged.
- The guard's behaviour for features at `none` is byte-identical.

---

## 7. Build order

One tree on branch `v0.5` from `main`; agents edit only their files and never
commit; I run the gate after each wave and commit.

| Wave | Agent | Model · effort | Owns |
| --- | --- | --- | --- |
| 1 | **scripts** | sonnet · high | `ac-check.sh`, `ac-tests/{common,pytest,generic,combine}.sh`, `task-*-gate.sh`, `make-briefs.sh`, `status.sh`, `lib.sh`, `kickoff.sh`, `signoff-check.sh`, `security-check.sh`, `ownership-guard.sh`, `tests/*-selftest.sh`, `tests/run-all.sh` |
| 1 | **templates** | sonnet · medium | `skills/kickoff/templates/security/**` |
| 2 | **prompts** | opus · high | `agents/{product,lead,senior}-engineer.md` (incl. the catalogue), `agents/code-reviewer.md`, `skills/{build,signoff,kickoff}/SKILL.md` |
| 3 | **evals** | sonnet · high | `plugins/plumbline/evals/**` |
| 3 | **docs** | sonnet · medium | README, `docs/dev-plan-v0.4.md` §17, `docs/evals/**`, `tests/smoke/**` |
| 4 | **reviewer** | sonnet · high, read-only | one fresh-eyes pass over the diff |

Gate after each wave: `bash tests/run-all.sh` (both TMPDIR modes),
`claude plugin validate ./plugins/plumbline --strict` and `claude plugin
validate .`, `git diff --stat` against each agent's files.

## 8. Tests

### 8.1 Self-tests

- **signoff-check and security-check:** level none adds nothing and runs
  nothing; each gap in §6.4 item 4 (missing file, unrecorded raise, unknown
  token, missing heading, empty plan, empty or `mismatch` `Checked`, a SEC ID
  that fails or is missing when run, a surface not in the profile, a blank or
  `none` AC tests cell, a secrets hit, open Critical and High, `fixed` without
  `verified`, missing independent pass). The run uses a fixture profile whose
  AC tests cell is a stub command (the generic adapter) that prints pass, fail
  or nothing per ID, so the self-test needs no real runner; one case runs a
  real node adapter end to end. Waivers accepted only when filled in; `Risk
  accepted:` covers exactly its row (whitespace and case folded) and a
  rewritten row is uncovered; `Risk accepted: secret` covers its path only;
  waiving `attacks` doesn't waive `independent`; `--no-run` skips only the run.
- **secrets scan:** hits on a private-key block, an added `.env`, `AKIA…`,
  `sk_live_`, `ghp_`, `xoxb-`; no hit on `.env.example`, a `pk_live_` key,
  `password = ` in prose, or a removed line.
- **kickoff:** `--security` at creation; `--set-security` creates the file,
  refuses to lower, no-ops on the same level, rejects unknown tokens; legacy
  phase; existing file never overwritten.
- **guard:** an agent cannot add `Security waived:` or `Risk accepted:` (Write,
  Edit, Bash) nor run `kickoff.sh --set-security`; the main session can; a
  mention mid-sentence is allowed; features at `none` behave as before.
- **IDs:** `SEC-` pass, fail and missing through node, pytest, go, playwright,
  generic and `combine.sh`; `SEC-03-001` never selects `AC-03-001`'s test (and
  the reverse); `AC-` output unchanged; task gates accept a SEC-only subject;
  `make-briefs` attack section with the fixtures line; `status` line.
- **Parsing and locks:** a row after a blank line, a `|` inside a finding, a
  missing header and an unknown severity are gaps; the guard allows "Risk
  accepted:" headings in ADRs and a `git commit -m` or `grep` mentioning it, and
  blocks the line only in `security.md`; `--set-security` exit codes, a
  `.plumbline` with no trailing newline, and the legacy phase's first
  `.plumbline`.
- **Compatibility:** the v0.4b self-tests pass unchanged (1,289 checks); a
  fixture feature with no security key produces byte-identical output.

### 8.2 Evals (what an eval run can see)

New cases (3 runs each), graded from file writes and the last message:
- `triage-security-auth` (expects `independent`), `triage-security-byid`
  (`attacks`), `triage-security-copy` (`none`);
- `lead-writes-attack-plan`: a multi-tenant fixture with a by-id read and a
  role check; checks the `## Attack plan` table with `Surface`, concrete
  attacks and "Must happen", `Signals:`, `Attack surface:` and `Attack
  fixtures:` lines, catalogue coverage (a cross-tenant read by ID and a
  tenant-filter-less list row, or a `Skipped:` line for them), `Attacks:`
  lines on tasks, SEC IDs in task subjects, no application code written;
- `senior-writes-attack-tests-first`: trace-order regex as in
  `senior-writes-unit-and-e2e` (the attack test file is written before the
  source file), uses the named fixtures, plus an LLM check of scope;
- `attacker-finds-planted-hole`: a fixture API whose by-id read skips the
  tenant check, with an `Attack surface:` that names it; checks a Findings row
  of severity critical or high, an Own attacks row and its test written, and
  no Write or Edit to the source file (trace);
- `reviewer-flags-soft-attack-test`: one SEC test that asserts nothing real and
  a plan missing an obvious catalogue item; checks the reviewer marks the
  mismatch and names the missing item;
- `quick-by-id-gets-attacks`: the Quick by-id lookup carries attack rows and
  tests (`quick-review-loop` keeps its graders).

Reruns, because their prompts change: the `triage-*`, `product-*`, `lead-*`,
`senior-*`, `reviewer-*` and the two Quick cases, so every earlier case holds
its score. Estimated **$20–30 at list price** (the v0.4b lean reruns cost about
$30). Keep the change only if each rerun holds its score.

### 8.3 Live test

The DineFlow staff portal (Clerk sign-in, per-restaurant order queue) runs on
`v0.5` after the PR: triage should print `Security: independent`; the lead
writes an attack plan from the catalogue (cross-restaurant order reads, an
unfiltered list, unsigned and expired requests, a forged restaurant ID, a role
claim in the body) with an `Attack surface:` and fixtures; authors build the
fixtures first and write the attacks as tests first; the reviewer checks them;
the attacker runs after the build, scoped; signoff runs the SEC tests and the
secrets scan and passes with no open Critical or High. We record from the
subagents' metadata that the attacker ran as Sonnet at high effort, the cost
of each security step, the wall time of signoff's test run, and what the
attacker found that the plan and the Opus reviewer didn't, so we can decide
whether D5 stays a default.

## 9. Definition of done

- All self-tests pass on both layouts, both TMPDIR modes; validation clean.
- Every earlier eval case at or above its v0.4b score; the six new cases at
  2 of 3 or better after fixes noted in the report.
- `docs/evals/eval-v0.5.md` and the README describe the levels, the catalogue,
  the attack plan and the flows.
- The DineFlow run behaves as in §8.3 or the gaps are fixed.
- PR opened against `main`, credited to Safi only; stop for review.

## 10. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| The author and the attacker are the same model with the same blind spots | The lead (Opus) writes the attacks from a catalogue; the reviewer flags missing items; the independent pass adds its own; HIGH tasks get the Opus reviewer |
| An agent writes a result without the work | SEC results are run at signoff and can't be faked. `Checked`, severity and `Independent pass:` are claims (rule 13): the lead's review and the independent pass cover them; the live run checks it did not happen |
| A weak attack test passes but proves nothing | The reviewer's security lens, `Checked` must be `matches`; the evals include a planted soft test |
| Signoff's test run is slow or needs servers | Only the SEC IDs run (a handful); the skill makes sure the Run commands are up (QA just used them); unit-level attacks need no server |
| The secrets scan cries wolf | Narrow prefixes and file names only; example env files excluded; a user-only acceptance per path |
| Over-triggering makes every feature `independent` | The rubric names the `none` examples; the user can waive a part; the eval set includes a `none` and an `attacks` case |
| Under-triggering misses a risky change | The lead can raise on its plan; the user can raise at two questions; signoff compares the levels |
| The attacker costs too much | One scoped Sonnet run, only at `independent`; the DineFlow run records the cost before we judge it |
| Eval runs can't see the order across agents | Order is proven in the live run; evals check each agent's own behaviour |
| The ID widening breaks an adapter | Self-tests per adapter; `AC-` output byte-checked |

## 11. Rollback

Revert the PR. Features created before the change have no `security=` key and
never see the new rules (rule 8). A feature created on v0.5 keeps a
`security.md` that older versions ignore.

## 12. Checklist

- [ ] Safi approves D1–D10 (or changes them)
- [x] One independent review of this plan against the code, findings fixed (revision 6b)
- [x] Branch `v0.5` from `main`
- [ ] Wave 1 (scripts, templates) and its gate
- [ ] Wave 2 (prompts) and its gate
- [ ] Wave 3 (evals, docs), then the reviewer pass and fixes
- [ ] Eval reruns and the new cases
- [ ] PR (credit Safi only)
- [ ] DineFlow staff portal live run, token report

## 13. Revision 6b: what the independent review changed

A Sonnet reviewer read revision 6 against the code (nine findings, all
confirmed) and the plan changed as follows:
1. **ID matching** is not one regex in seven files: the adapters build filters
   from the numbers alone (`common.sh`, `pytest.sh`, `generic.sh`, `combine.sh`).
   §4, §6.4.1 and §6.7 now name every site and require the prefix to come from
   the ID, with tests that SEC never selects AC.
2. **Gates satisfiable without work:** an empty attack plan is a gap; each SEC
   ID needs a real result (revision 7 made that a run, see §14); acceptances
   repeat the row; the plan no longer claims Ownership stops self-grading.
3. **The guard** no longer widens for every file: the new phrases apply to
   `security.md` only, with their own message; the script lock is described as
   best effort.
4. **No task gate without a team:** the lead runs `ac-check` for SEC IDs itself.
5. **Quick:** the lead opens the PR, so the lead's Quick rule changes; Quick SEC
   IDs are `SEC-<yymmdd>-<nn>`.
6. **Handoff to the user:** a "Needs user" return, as for evidence waivers.
7. **`md_table` fragility:** `security_rows` is its own parser.
8. **`kickoff.sh`:** exit codes, `--set-security` before the positional parse,
   `none` writes no key, trailing newline, the legacy phase's first
   `.plumbline`.
9. **Smaller:** `Independent pass: complete (round <n>)` (the dispatch has no
   name); HIGH work already gets the Opus reviewer.

## 14. Revision 7: the cost-and-quality pass

What changed from 6b and why:
1. **Signoff runs the SEC tests** (`ac-check` per surface) instead of reading a
   pasted result line. A pasted line is text an agent can type; a run is not.
   The `Test` and `ac-check` columns are gone; `security.md` shrinks to the
   independent-pass line, Own attacks and Findings; the reviewer's verdict is a
   `Checked` column on the attack plan itself. Cost: wall time for a handful of
   tests, and the skill keeps the apps up for them (D9).
2. **The attacker is scoped** to an `Attack surface:` line the lead writes, so
   it loads the risky routes and pages, not the whole feature, and its attacks
   stay attacks rather than feature complaints.
3. **The "three own attacks" signoff gate is gone.** A count invites padding;
   the attacker's own tests are run like the plan's and the prompt sets the
   norm.
4. **An attack catalogue per signal** (about 40 lines in the lead's prompt)
   with `Skipped:` lines for items left out. It makes plans consistent and
   fast, gives the reviewer a checklist to flag gaps against, and gives the
   evals something deterministic to grade.
5. **Shared attack fixtures** are named in the plan with the task that builds
   them first, so engineers don't each invent a second tenant or a forged
   token.
6. **A secrets scan** at `attacks` and above: deterministic, free, narrow
   patterns; user-only acceptance per path (D10).
7. **Rule 13** says plainly which gates run things and which read claims, and
   stops adding columns to the second kind.
