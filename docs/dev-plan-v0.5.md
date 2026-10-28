# Plumbline v0.5 dev plan: security by attack plan

Status: DRAFT (revision 6), awaiting Safi's approval
Owner: Safi
Written: 2026-10-28, from `main` at e45c66e (v0.4b merged: lean roles).

Revision 6b (2026-10-28) folds in an independent review of revision 6 against
the code (nine findings, all confirmed: §13). Revision 6 replaces revision 5 (1,128 lines: an Opus security engineer, a
plan-review gate chain, hashes and stale verdicts; four break-tests found 99
holes in it). It stays in git history. Safi's direction on 2026-10-28 made the
design smaller and cheaper: **the lead plans the attacks, the engineer who
writes the code writes them as tests first, a reviewer checks the tests really
attack, and a different engineer attacks the finished feature only when the
risk is high.** No new agent type, no plan-review gates.

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
   **attack plan** in `dev-plan.md`: concrete attacks, each with an ID
   (`SEC-03-001`) and what must happen. The engineer who builds the feature
   writes each attack as a failing test first, then makes it pass. The reviewer
   (Sonnet; Opus for HIGH work, which the risky signals usually are) reads every
   attack test against its plan row and reports any that doesn't really attack.
   Signoff needs every `SEC-` ID to pass.
3. **`independent` (high risk only).** After the build, a **different** Sonnet
   engineer attacks the finished feature: it runs the lead's attacks, tries
   the ones the plan missed, writes attack tests of its own and logs findings.
   The authors fix; the attacker re-runs. Signoff needs the pass done and no
   open Critical or High finding.
4. **Routine work pays nothing.** At `none`, no attack plan, no extra pass, no
   new file: the reviewer's existing security checklist is all there is.
5. **Quality bars hold:** the attacker never edits the code it attacks, no agent
   writes the user's lines, and every v0.4b eval case keeps its score.

## 2. Scope

**In:**
- the `Security:` triage line and rubric (§6.2);
- the attack plan in `dev-plan.md` and `security.md` per feature (§6.3);
- `SEC-` IDs through the ID-matching scripts, the task gates, briefs and the
  adapters (§6.4);
- signoff rules and the user-only waiver and risk-acceptance lines (§6.4);
- prompt changes for product, lead, senior engineer and code reviewer (§6.5);
- the flows: Standard, Full, Quick (§6.6);
- self-tests, evals, README.

**Out (later releases):**
- external scanners (SAST, DAST, dependency audits);
- a separate security agent type or an Opus attacker as a default;
- penetration tests of deployed environments;
- module-level threat models or a security section in `vision.md`;
- risk acceptance in Quick (a Quick change with an open Critical or High
  finding is fixed or re-triaged).

## 3. Working rules (carried from v0.4)

1. **Quality guard.** `docs/evals/eval-v0.4b.md` is the baseline. Any case that
   scores below it after a change is fixed or the change is reverted.
2. **Deterministic gates.** Pass/fail is decided by scripts (bash and jq):
   the level, open findings, SEC results, waivers.
3. **Nothing ships untested.** Scripts and hooks: self-tests on both layouts
   and both TMPDIR modes. Agents and skills: evals. The whole flow: a live run.
4. **One PR, branch `v0.5` from `main`,** evals on it, stop for review.
5. **Commits and PRs credit Safi only.** No co-author trailer, no footer.
6. **Helper files go in `$TMPDIR`,** never in `D:\Repos`.
7. **Evals run with `--no-publish`, `--ablation none`, 3 runs per case,** cheap
   cases first, one group at a time, concurrency by free RAM.
8. **Backward compatible.** A feature with no `security=` key and no
   `Security level:` line behaves exactly as in v0.4b: no new gaps, context,
   dispatches or refusals, the same templates and files.
9. **Agents never write the user's lines,** never edit permission settings, and
   are dispatched without a `name` unless the step spawns teammates.
10. **The lead is always Opus and never writes application code.** Engineers
    are Sonnet; the attacker is a Sonnet engineer.
11. **Fail closed where security is in play.** When a feature's level is not
    `none`, an unknown level token, a malformed row or a missing table is a
    gap. Where it is `none`, nothing new happens (rule 8).
12. **One mechanism per threat** (§6.8). A mechanism without a row there is
    dropped.

## 4. Facts from the v0.4b code that shape this plan

| Fact | Consequence |
| --- | --- |
| The ID pattern `AC-[0-9]+-[0-9]+` is read in `ac-check.sh` (the ID list and the output filter), `ac-tests/combine.sh` (the normaliser and two result filters), `make-briefs.sh`, `task-completed-gate.sh` and `task-created-gate.sh`. The adapters build their runner filter from the numbers alone: `common.sh` splits `AC-a-b` into `a` and `b`, `pytest.sh` selects `ac_<a>_<b>`, `generic.sh` has its own parser and `AC` placeholders | A SEC ID would select the AC test with the same numbers, or come back "missing". Every one of these sites takes the prefix from the ID (`AC` or `SEC`), and a self-test proves `SEC-03-001` never selects `AC-03-001`'s test |
| `signoff-check.sh` and `status.sh` read documents (criteria, Traceability, test files) and never run tests; only the TaskCompleted gate and `ac-check.sh` do | The SEC reads in signoff are new code, not a widened regex; `status.sh` coverage stays `AC-` only |
| TaskCompleted fires only for teammates (the gate exits 0 without a teammate name); a Standard feature built by subagents has no task gate | The lead runs `ac-check` on each workstream's SEC IDs and pastes the pass line into `security.md`; signoff checks the pasted line and that a tracked test file holds the ID |
| The guard checks waiver lines on every agent write to every file, before it knows whether a build is active, and its Bash check matches anywhere in the command | The new phrases are checked only for files named `security.md` (Write and Edit by path; Bash only when the command writes to `security.md`), with their own message. ADRs, threat models, SECURITY.md and commit messages are unaffected |
| The template Ownership rows `product` and `qa` are `docs/product/**` (`*` crosses `/`), and plain subagents skip the Ownership check | We can't claim only the lead writes `security.md`. Gates catch omission, not forgery, as in v0.4b (the QA verdict, the evidence rows). The controls against self-grading are the pasted `ac-check` line, the test-file check and the lead's review |
| `md_table` treats a row after a blank line as a new header and splits on every `\|` | `security_rows` is its own parser: it requires the exact header, counts every `\|` line up to the next heading, and any line it can't read, or a row with the wrong cell count, is a gap |
| The guard blocks `Evidence waived:` and `Accessibility waived:` line-starts and writes to `.plumbline` and `project.md`; its Bash rules are best effort (the guard's own header says so) | The same style of lock for the two new lines in `security.md`; `.plumbline` is already locked. The Bash lock on `kickoff.sh --set-security` is best effort too, backed by the signoff rule that a raise must be recorded |
| `evidence_waived` accepts a line only when filled in (no `<placeholder>`, ends with `(approved by <name>)`) | The new lines reuse that rule through one shared helper |
| `kickoff.sh`: exit 1 is usage or "exists", 2 is `--new-module`; the legacy form copies every file in `templates/phase/`, has no `.plumbline` today, and `tests/kickoff-selftest.sh` asserts that | `security.md` lives in `templates/security/`, copied only by `--set-security` and `--security`; those exit 0 or 1 only; a legacy phase gets its first `.plumbline` only when a level above `none` is set |
| In Quick the lead pushes and opens the PR itself (`lead-engineer.md` Quick step 6, `build/SKILL.md`), and Quick IDs are `AC-<yymmdd>-<nn>` | The lead's Quick rule changes (no PR while a SEC row fails or a Critical or High finding is open); Quick SEC IDs are `SEC-<yymmdd>-<nn>` |
| The lead runs as a subagent and can't ask the user | A "Needs user" return to the build skill, which asks, writes the user's lines and re-dispatches the lead (the pattern for evidence waivers) |
| The code reviewer is read-only; HIGH workstreams get the Opus reviewer (`lead-engineer.md`) | The lead records the reviewer's SEC verdicts; auth, billing and tenancy work is HIGH, so `independent` features get the Opus reviewer on their riskiest tasks without extra rules |
| `make-briefs.sh` keeps each engineer's tasks and the `## Screen descriptions` it needs | The brief gets the engineer's attack rows the same way |
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
- **D2 Risk acceptance:** the user may accept an open Critical or High finding
  in a user-only line, never in Quick.
- **D3 Quick:** may carry `attacks` (inline in the lead's plan, no feature
  folder); `independent` is never Quick, triage sizes it Standard at least.
- **D4 Full** features get at least `attacks`.
- **D5 The independent attacker** is a fresh Sonnet senior engineer at high
  effort, dispatched by the lead after every workstream is accepted and before
  QA. An Opus reviewer (with the security lens) reads the diff for HIGH tasks,
  as it already does in lean roles.
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

---

## 6. Specification

### 6.1 Levels

| Level | Meaning | Written as |
| --- | --- | --- |
| none | the reviewer's existing security checklist is enough | `none` |
| attacks | the lead's attack plan; the author's attack tests; the reviewer's check of them; signoff needs every SEC test passing | `attacks` |
| independent | `attacks`, plus an independent attack pass by a different engineer and no open Critical or High finding | `independent` |

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
`none`; otherwise the highest matching row wins.

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
| SEC ID | Workstream | Attack | Must happen |
| --- | --- | --- | --- |
| SEC-03-001 | eng-api | Staff of restaurant B calls GET /orders/<id of an order of restaurant A> with a valid session | 404, nothing from the order in the body |
```

Rules: one to eight rows; at least one per rubric signal that matched; each
attack is a concrete request, input or action, never a topic ("check authz");
IDs are `SEC-<nn>-<nnn>`, `nn` the feature number as in `AC-<nn>-…` (Quick:
`SEC-<yymmdd>-<nn>`, as its `AC-` IDs). Cells contain no `|`. Each task line
lists the SEC IDs it must withstand in an `Attacks:` line, and the task
subject carries them: `[AC-03-004 SEC-03-001] Order list API`. "Done when"
includes those tests passing. At `attacks` or above the lead adds
`docs/product/**/security.md` to its own Ownership row.

**`security.md`** (feature folder, from `templates/security/security.md`,
created by `kickoff.sh --set-security` or `--security` the first time the level
is `attacks` or above; never over an existing file):

```
# Phase <phase> security

Independent pass: not started

## Attacks
| SEC ID | Test | ac-check | Checked by |
| --- | --- | --- | --- |

## Findings
| # | Severity | Finding | Status | Evidence |
| --- | --- | --- | --- | --- |
```

- **Attacks:** one row per SEC ID in the attack plan, written by the lead after
  it runs `ac-check` for that workstream and gets the reviewer's verdict.
  `Test` is the tracked test file holding the ID; `ac-check` is the pasted
  output line (`SEC-03-001: pass (1)`); `Checked by` is the reviewer's verdict,
  starting `matches` or saying what is wrong. The attacker adds a row for each
  attack of its own (IDs continuing the numbering) with its test and its
  `ac-check` line.
- **Findings:** written by the attacker; no `|` in any cell. Severity:
  **critical** (another tenant's or user's data readable or writable, auth
  bypass, money wrong), **high** (personal data leaked, privilege escalation
  inside a tenant, injection with a shown effect), **medium** and **low**
  (reported, not blocking). Status: `open`, `fixed` (the owner says so),
  `verified` (the attacker re-ran the attack and it is blocked).
- **`Independent pass:`** is `not started`, `not needed` (level `attacks`) or
  `complete (round <n>)`, written by the attacker when its pass is done.

**Quick** has no feature folder: the lead's inline plan carries the attack
lines and its final report lists each SEC ID with its `ac-check` line (§6.6).

**User-only lines** (the build skill writes them in `security.md`, only after
the user says so):
- `Security waived: <attacks|independent> - <reason> (approved by <name>)`
- `Risk accepted: #<n> <severity> <the finding text exactly as in the row> - <reason> (approved by <name>)`.
  Editing the row afterwards voids the acceptance.

### 6.4 Gates and locks

1. **IDs.** Every site in §4 row 1 takes the prefix from the ID: the ID list and
   output filter in `ac-check.sh`; the normaliser and the two result filters in
   `combine.sh`; the runner-filter builder in `common.sh` (it keeps the prefix
   instead of dropping it); `pytest.sh` (`sec_<a>_<b>` for a SEC ID, `ac_<a>_<b>`
   for an AC ID); `generic.sh` (its parser and its `AC` placeholders); and the
   task gates and `make-briefs.sh`. Output prints the ID as given
   (`SEC-03-001: pass (1)`). A SEC-only task subject is accepted. `status.sh`
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
3. **`scripts/security-check.sh`** (new, read-only) prints the recorded level,
   the required level, each SEC ID of the attack plan with its result, the open
   Critical and High findings, the independent-pass state and any format gap.
   The build skill and the lead call it; `signoff-check.sh` shares its parser
   (`security_*` helpers in `lib.sh`).
4. **`signoff-check.sh`** adds these rules only when the recorded level is not
   `none` (rule 8); every row is read by `security_rows` (§4), so an unreadable
   line is a gap, not a silent drop:
   - `security.md` missing, an unknown level token, or a missing `## Attacks` /
     `## Findings` heading → gap;
   - the lead's `Security level:` line is higher than `.plumbline security=` →
     gap `raise not recorded; run --set-security`;
   - **unless `attacks` is waived:** the `## Attack plan` exists and has at
     least one row (an empty or missing plan is a gap); each SEC ID in it has a
     row in `security.md` Attacks whose `ac-check` cell starts `<ID>: pass` and
     whose `Checked by` starts `matches`, and the ID appears in a tracked file
     (`git ls-files` under the feature's surfaces' Paths, or outside `docs/` if
     it has none) → gap per ID;
   - **open findings:** a Critical or High row whose Status isn't `verified`
     and that no matching `Risk accepted:` line covers → gap per row;
   - **at `independent`, unless `independent` is waived:** `Independent pass:`
     is `complete (…)`, and Attacks holds at least three rows whose IDs are not
     in the attack plan, each with a test file and a pass line → gap;
   - waiver and acceptance lines count only when filled in (no `<…>`
     placeholder, ends `(approved by <name>)`); an acceptance must repeat the
     row's severity and text exactly.
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
   Ownership to stop self-grading (§6.8).
7. **`make-briefs.sh`** adds `## Attacks to withstand` to each brief: the attack
   plan rows for the SEC IDs in that engineer's tasks. No section when it has
   none.
8. **`status.sh`** adds one line when the level is not `none`:
   `security: <level> · SEC <pass>/<total> · open high <n>`.

### 6.5 Agents

All prompt changes are small additions in the existing files; none adds an
agent type.

**`product-engineer.md`** (triage mode): the block's `Security:` line and the
rubric of §6.2 in a compact table; `independent` makes the size at least
Standard; criteria are unchanged (attacks are not acceptance criteria).

**`lead-engineer.md`:**
- At `attacks` or above, write `## Attack plan` (§6.3) before the user approves
  the plan, and add `Attacks:` lines to the tasks that build the attacked code;
  add the `Security level:` line when the plan shows a rubric signal triage
  missed.
- Review each workstream: run `ac-check` for its SEC IDs (as for its AC IDs;
  without a team nothing else runs them), and dispatch the reviewer told
  "Security lens" (Sonnet; Opus for HIGH tasks, as now): for every SEC ID in the
  workstream, read its test against the plan row and say whether it sends the
  attack and asserts the "Must happen" (a test that can't fail, asserts a
  status only, or attacks something else is a mismatch). Write the row into
  `security.md` Attacks with the pasted `ac-check` line and the verdict.
- At `independent`, after every workstream is accepted and before QA, dispatch
  one fresh `senior-engineer` (model sonnet, effort high, no name) with the
  attack brief (§6.6). Route each finding to the engineer who owns the code,
  ask the attacker to verify the fix, and stop after three rounds (D6) with a
  "Needs user" return listing the open rows.
- Quick: push and open the PR only when every SEC row shows its pass line and no
  Critical or High finding is open; otherwise stop and report the rows.
- Never writes code or the user's lines.

**`senior-engineer.md`:**
- **Author mode** (the brief has `## Attacks to withstand`): for each SEC ID,
  write the attack as a test first (a hostile caller doing exactly what the row
  says, asserting the "Must happen"), see it fail, then make it pass. Put the
  SEC ID in the test title, never in a file name. Report each SEC test's first
  failing run.
- **Attack round** (the dispatch says "Attack round"): never edit the code
  under attack or the authors' tests. Run the lead's attacks, then write at
  least three of your own that the plan missed (other callers, other tenants'
  IDs, missing and malformed input, replay, state out of order), each as a real
  request or action. Write each as an attack test in your own file inside the
  surface's test folder (title starts with a new SEC ID), add an Attacks row
  with its `ac-check` line, and for each confirmed break a Findings row
  (severity per §6.3, the failing run as evidence, no `|` in cells). After the
  authors fix, re-run and mark `verified`. Finish by writing `Independent pass:
  complete (round <n>)` and report findings by severity. Do not soften a
  severity to make the pass easier; say so when you are unsure.

**`code-reviewer.md`:** when the dispatch says "Security lens", read each named
SEC test against its plan row and return a table `SEC ID | matches | note`;
otherwise unchanged (the existing checklist stays).

**`qa-engineer.md`:** unchanged. QA tests the final code after the attack round.

**`skills/build/SKILL.md`:** prints the `Security:` line in the triage block;
at the plan-approval question lists the level and says the user can raise it or
waive a part; runs `--set-security` and `--security`; after the build, at
`independent`, has the lead run the attack round before QA; when the lead
returns "Needs user" it asks per open row, writes the `Security waived:` and
`Risk accepted:` lines only after the user says so (the same procedure as
evidence waivers) and re-dispatches the lead; in Quick it relays a stopped PR. `skills/signoff/SKILL.md` and `skills/kickoff/SKILL.md` mention the
file and the rules.

### 6.6 Flows

**Standard** (level from triage; the build skill creates the folder with
`kickoff.sh … --security <level>`):

1. Product writes spec, criteria and `ux.md` (as now).
2. The lead writes the dev plan **with the attack plan** and `Attacks:` lines.
3. One user approval (the level is shown; raise or waive here). READY, briefs.
4. Build: authors write unit, e2e and attack tests first. The lead reviews each
   workstream; the Sonnet reviewer runs with the security lens.
5. At `independent`: attack round (below), then the authors' fixes.
6. QA tests the flows; product verifies; signoff-check; PR.

**Full:** the same after discovery; at least `attacks` (D4).

**Attack round** (the lead dispatches the attacker with: the attack plan, each
workstream's summary and surface, the run commands from the profile, and
"Attack round"):
1. Attacker runs the plan's attacks and its own; writes tests and findings.
2. Lead sends each open Critical or High finding to its owner; the owner fixes
   with a failing attack test first.
3. Attacker verifies; findings become `verified`. Repeat up to three rounds.
4. Open rows after round three: the lead returns "Needs user" with the rows;
   the build skill asks (fix again, `Risk accepted:` (D2) or stop), writes the
   user's lines and re-dispatches the lead.

**Quick** (`attacks` only): the lead's inline plan carries the attack lines
(`SEC-<yymmdd>-<nn>`); the engineer writes the attack tests first; the
reviewer runs with the security lens; the lead runs `ac-check` for them and
its final report lists each SEC ID with the pass line. The lead pushes and
opens the PR only if every row passes. A Quick change that turns out to need
`independent` is stopped and re-triaged to Standard.

### 6.7 Scripts and interfaces (summary)

| Piece | Change |
| --- | --- |
| `ac-check.sh`, `ac-tests/{common,pytest,generic,combine}.sh`, task gates, `make-briefs.sh` | the prefix comes from the ID (`AC` or `SEC`) |
| `lib.sh` | `security_level`, `security_required`, `security_rows` (own table parser) helpers; one shared "filled-in approved line" helper |
| `kickoff.sh` | `--security <level>`, `--set-security <level>`; `templates/security/security.md` |
| `security-check.sh` (new) | read-only report of §6.4 item 3 |
| `signoff-check.sh` | the rules of §6.4 item 4 |
| `ownership-guard.sh` | `Security waived:` and `Risk accepted:` in `security.md` only, and the best-effort script lock |
| `make-briefs.sh`, `status.sh` | attack section; one status line |
| Templates | `templates/security/security.md` is new; `templates/phase/dev-plan.md` is unchanged (rule 8: the lead adds the Attack plan section and its Ownership path only when the level needs them) |

### 6.8 One mechanism per threat

| Threat | Mechanism |
| --- | --- |
| Security work skipped on a risky change | Triage rubric in the block; the lead's raise; `signoff-check` compares the recorded and required level |
| The lead's attacks never become tests | SEC IDs in task subjects (task gate with a team, the lead's `ac-check` without one); signoff needs the pasted pass line and a tracked test file holding the ID; an empty plan is a gap |
| A test that cannot fail | The reviewer's security lens reads each test against its row; `Checked by` must start `matches` |
| An agent writes `pass` without doing the work | Honest limit: gates catch omission, not forgery, as in v0.4b. Controls: the pasted `ac-check` line, the test-file check, the lead's summary review and the independent pass |
| Shared blind spots between author and the plan | The independent pass at `independent`: at least three attacks of its own beyond the plan, each with a test |
| The attacker "fixes" what it found | The attacker never edits attacked code; findings go to the owner |
| A High finding ignored or its row rewritten | Signoff gap unless `verified` or a `Risk accepted:` line that repeats the row exactly |
| An agent lowers its own bar | Waivers and acceptances are user-only lines the guard blocks in `security.md`; levels only go up |
| Level drift | The lead's `Security level:` line without `--set-security` is a signoff gap |
| A malformed table hides a finding | `security_rows` counts lines against rows and gaps on any it can't read |

### 6.9 Compatibility invariants (must not change)

- A feature with no `security=` key and no `Security level:` line: no new gap,
  file, context line, status line, dispatch or refusal.
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
| 1 | **scripts** | sonnet · high | `ac-check.sh`, `ac-tests/{common,combine}.sh`, `task-*-gate.sh`, `make-briefs.sh`, `status.sh`, `lib.sh`, `kickoff.sh`, `signoff-check.sh`, `security-check.sh`, `ownership-guard.sh`, `tests/*-selftest.sh`, `tests/run-all.sh` |
| 1 | **templates** | sonnet · medium | `skills/kickoff/templates/security/**` |
| 2 | **prompts** | opus · high | `agents/{product,lead,senior}-engineer.md`, `agents/code-reviewer.md`, `skills/{build,signoff,kickoff}/SKILL.md` |
| 3 | **evals** | sonnet · high | `plugins/plumbline/evals/**` |
| 3 | **docs** | sonnet · medium | README, `docs/dev-plan-v0.4.md` §17, `docs/evals/**`, `tests/smoke/**` |
| 4 | **reviewer** | sonnet · high, read-only | one fresh-eyes pass over the diff |

Gate after each wave: `bash tests/run-all.sh` (both TMPDIR modes),
`claude plugin validate ./plugins/plumbline --strict` and `claude plugin
validate .`, `git diff --stat` against each agent's files.

## 8. Tests

### 8.1 Self-tests

- **signoff-check:** level none adds nothing; each gap in §6.4 item 4 (missing
  file, unrecorded raise, unknown token, missing heading, SEC not pass, empty
  or mismatched `Checked by`, open Critical and High, `fixed` without
  `verified`, missing independent pass); waivers accepted only when filled in;
  `Risk accepted:` covers exactly its row; waiving `attacks` doesn't waive
  `independent`.
- **kickoff:** `--security` at creation; `--set-security` creates the file,
  refuses to lower, no-ops on the same level, rejects unknown tokens; legacy
  phase; existing file never overwritten.
- **guard:** an agent cannot add `Security waived:` or `Risk accepted:` (Write,
  Edit, Bash) nor run `kickoff.sh --set-security`; the main session can; a
  mention mid-sentence is allowed; features at `none` behave as before.
- **IDs:** `SEC-` pass, fail and missing through node, pytest, go, playwright,
  generic and `combine.sh`; `SEC-03-001` never selects `AC-03-001`'s test (and
  the reverse); `AC-` output unchanged; task gates accept a SEC-only subject;
  `make-briefs` attack section; `status` line.
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
- `lead-writes-attack-plan`: a multi-tenant fixture; checks the `## Attack plan`
  table with concrete attacks and "Must happen", `Attacks:` lines on tasks,
  SEC IDs in task subjects, no application code written;
- `senior-writes-attack-tests-first`: trace-order regex as in
  `senior-writes-unit-and-e2e` (the attack test file is written before the
  source file) plus an LLM check of scope;
- `attacker-finds-planted-hole`: a fixture API that skips the tenant check;
  checks a Findings row of severity critical or high, an attack test written,
  and no Write or Edit to the source file (trace);
- `reviewer-flags-soft-attack-test`: one SEC test that asserts nothing real;
  checks the reviewer marks it a mismatch;
- `quick-by-id-gets-attacks`: the Quick by-id lookup carries attack lines and
  tests (replaces nothing; `quick-review-loop` keeps its graders).

Reruns, because their prompts change: the `triage-*`, `product-*`, `lead-*`,
`senior-*`, `reviewer-*` and the two Quick cases, so every earlier case holds
its score. Estimated **$20–30 at list price** (the v0.4b lean reruns cost about
$30). Keep the change only if each rerun holds its score.

### 8.3 Live test

The DineFlow staff portal (Clerk sign-in, per-restaurant order queue) runs on
`v0.5` after the PR: triage should print `Security: independent`; the lead
writes an attack plan (cross-restaurant order reads, unsigned requests, a
forged restaurant ID); authors write the attacks as tests first; the reviewer
checks them; the attacker runs after the build; signoff passes with no open
Critical or High. We record from the subagents' metadata that the attacker
ran as Sonnet at high effort, and the cost of each security step, so we can
tell whether `independent` earns its price.

## 9. Definition of done

- All self-tests pass on both layouts, both TMPDIR modes; validation clean.
- Every earlier eval case at or above its v0.4b score; the six new cases at
  2 of 3 or better after fixes noted in the report.
- `docs/evals/eval-v0.5.md` and the README describe the levels, the attack
  plan and the flows.
- The DineFlow run behaves as in §8.3 or the gaps are fixed.
- PR opened against `main`, credited to Safi only; stop for review.

## 10. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| The author and the attacker are the same model with the same blind spots | The lead (Opus) writes the attacks; the independent pass adds its own beyond the plan; HIGH tasks get the Opus reviewer |
| An agent writes `pass` or `verified` without the work | Gates catch omission, not forgery (as with the QA verdict). The pasted `ac-check` line, the tracked-test-file check, the lead's review and the independent pass make it costly; the live run checks it did not happen |
| A weak attack test passes but proves nothing | The reviewer's security lens, `Checked by` must say `matches`; the evals include a planted soft test |
| Over-triggering makes every feature `independent` | The rubric names the `none` examples; the user can waive a part; the eval set includes a `none` and an `attacks` case |
| Under-triggering misses a risky change | The lead can raise on its plan; the user can raise at two questions; signoff compares the levels |
| The attacker costs too much | One Sonnet run, only at `independent`; the DineFlow run records the cost before we judge it |
| Eval runs can't see the order across agents | Order is proven in the live run; evals check each agent's own behaviour |
| The ID widening breaks an adapter | Self-tests per adapter; `AC-` output byte-checked |

## 11. Rollback

Revert the PR. Features created before the change have no `security=` key and
never see the new rules (rule 8). A feature created on v0.5 keeps a
`security.md` that older versions ignore.

## 12. Checklist

- [ ] Safi approves D1–D8 (or changes them)
- [ ] One independent review of this plan against the code, findings fixed
- [ ] Branch `v0.5` from `main`
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
   ID needs a pasted `ac-check` line and a tracked test file; acceptances repeat
   the row; the plan no longer claims Ownership stops self-grading (§6.8 says
   what it does and does not stop).
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
   name); at least three attacks of its own are enforced by signoff; HIGH work
   already gets the Opus reviewer.
