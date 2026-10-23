# Plumbline

A Claude Code plugin that builds software phase by phase with a small agent team,
and checks every phase against the product docs before it ships.

| Role | Agent | Model | Owns |
| --- | --- | --- | --- |
| Product engineer | plumbline:product-engineer | opus | What is built: research, spec, use cases, acceptance criteria |
| UI/UX engineer | plumbline:ux-engineer | opus | How it works and feels: journeys, design brief, screens, prototypes, tokens, design principles |
| Lead engineer | plumbline:lead-engineer | opus, effort xhigh | How it is built: dev plan, team size, contracts, task order, review |
| Senior engineers | plumbline:senior-engineer | sonnet (opus for HIGH work) | One workstream each, test-first |
| QA engineer | plumbline:qa-engineer | opus | Test plan, the verdict |
| QA runner | plumbline:qa-runner | sonnet | Runs the plan: suites, browser journeys, accessibility, screenshots |
| Code reviewer | plumbline:code-reviewer | sonnet for NORMAL, opus for HIGH | Read-only fresh-eyes review |

Judgement-heavy work (product, design, planning, the QA plan) runs on opus;
procedural work (implementing a planned task, running a test plan) runs on sonnet.

## Skills

| Command | What it does |
| --- | --- |
| `/plumbline:kickoff <area> <phase-id>` | Creates the phase docs from templates, marks the phase current, branches |
| `/plumbline:discover [idea]` | Interviews you, then drafts spec.md from your answers |
| `/plumbline:status` | Plan status, AC test coverage, open bugs, questions, uncommitted work per owner |
| `/plumbline:handoff` | Records progress, commits the docs, prints a prompt to resume in a fresh session |
| `/plumbline:signoff` | Runs the gap check, then opens or updates the phase PR |

## Gates and context

Once the phase's dev plan says `Status: READY`, hooks enforce the gates:

- teammates edit only files they own (Ownership table);
- every task names the AC IDs it delivers (`[chore]` for coordination work), and
  completes only when typecheck, lint and those AC tests pass;
- nobody goes idle with uncommitted work: two reminders, then an ESCALATED row
  in questions.md that signoff won't pass.

At start-up the lead and each teammate get the phase, plan status, their
Ownership row, their brief and open questions injected, so nobody re-reads
everything to find their place. Engineers work from `briefs/<name>.md`, generated
from the plan and docs when the plan goes READY.

## Install

    claude plugin marketplace add safiullah7/plumbline
    claude plugin install plumbline@plumbline --scope project

## Use

    /plumbline:kickoff <area> <phase-id>
    /plumbline:discover
    ... spec, UX, test plan, dev plan, build, QA ...
    /plumbline:signoff

Requires Claude Code with agent teams (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 for
build sessions), Git Bash on Windows, and jq.

The task gate runs your repo's `typecheck`, `lint` and `test:ac` npm scripts
(override them with PLUMBLINE_TYPECHECK, PLUMBLINE_LINT and PLUMBLINE_TEST_AC in
`.claude/settings.json`). `test:ac "<AC IDs separated by |>"` must fail when any
of those IDs has no passing test named after it; many runners pass when a name
filter matches nothing. `tests/e2e/setup.sh` has a node:test example
(`scripts/run-ac-tests.js`).

For lower token use in long builds, set `"subagentPromptCacheTtl": "1h"` in your
Claude Code settings: teammates then reuse cached prompts for an hour.

## Tests

    bash tests/hooks-selftest.sh      # hook gates
    bash tests/scripts-selftest.sh    # status, signoff check, briefs, AC list
    claude plugin eval ./plugins/plumbline --scaffold --allow-tools Write Edit --ablation none --no-publish

The live team test is in `tests/smoke/README.md`. Eval baselines and token
measurements are in `docs/evals/`.
