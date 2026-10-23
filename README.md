# Plumbline

A Claude Code plugin that builds software phase by phase with a small agent team,
and checks every phase against the product docs before it ships.

| Role | Agent | Owns |
| --- | --- | --- |
| Product engineer | plumbline:product-engineer | What is built: spec, use cases, acceptance criteria |
| UI/UX engineer | plumbline:ux-engineer | How it works and feels: journeys, flows, screens, prototypes, design principles |
| Lead engineer | plumbline:lead-engineer | How it is built: dev plan, team size, contracts, review |
| Senior engineers | plumbline:senior-engineer | One workstream each, with tests |
| QA engineer | plumbline:qa-engineer | Test plan, independent testing, QA report |
| Code reviewer | plumbline:code-reviewer | Read-only fresh-eyes review |

Hooks enforce the gates: tasks complete only when their acceptance-criteria tests
pass, teammates edit only files they own, and nobody goes idle with uncommitted work.

## Install

    claude plugin marketplace add safiullah7/plumbline
    claude plugin install plumbline@plumbline --scope project

## Use

    /plumbline:kickoff <area> <phase-id>
    ... discovery, plan, build, verify, QA ...
    /plumbline:signoff

Requires Claude Code with agent teams (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 for
build sessions) and jq.
