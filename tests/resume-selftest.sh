#!/usr/bin/env bash
# Self-test for resume-state.sh (v0.6.1): the stage an interrupted feature resumes
# at, and the facts it prints. Run from the repo root:
#   bash tests/resume-selftest.sh
# Builds a feature folder in a temp repo and walks it through every stage.
set -u
if ! command -v jq >/dev/null 2>&1; then
  echo "jq isn't installed or isn't on PATH. Install it (Windows: winget install jqlang.jq),"
  echo "open a new terminal, check 'jq --version', then run this again."
  exit 1
fi
G="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/.claude" "$T/home/.claude" "$T/tmp"
cd "$T/repo" && git init -q -b main && git config core.autocrlf false && git config user.email t@t && git config user.name t
export HOME="$T/home" CLAUDE_PROJECT_DIR="$T/repo" TMPDIR="$T/tmp"
unset CLAUDE_CONFIG_DIR PLUMBLINE_TEAM

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
has()  { grep -qF -- "$2" <<<"$1"; }
state() { bash "$G/resume-state.sh" 2>&1; }
expect_next() { # name, stage
  local out; out=$(state)
  if has "$out" "Next: $2"; then ok "$1"; else fail "$1 (got: $(grep '^Next:' <<<"$out"))"; fi
}
expect_line() { # name, text
  local out; out=$(state)
  if has "$out" "$2"; then ok "$1"; else fail "$1 (wanted: $2)"; echo "$out" | sed 's/^/      /'; fi
}

# --- no active phase ---
out=$(state); rc=$?
[[ $rc == 1 ]] && has "$out" "no active phase" && ok "no current-phase: exit 1, says so" || fail "no current-phase (rc $rc)"

F=docs/product/shop/02-orders; mkdir -p "$F"; echo "$F" > .claude/current-phase
printf 'module=shop\nnumber=02\nprofile=full\nsurfaces=api,web-ui\nslug=orders\nsecurity=none\n' > "$F/.plumbline"
cat > "$F/acceptance-criteria.md" <<'EOF'
# Criteria
| ID | Criterion |
| --- | --- |
EOF
cat > "$F/signoff.md" <<'EOF'
# Feature 02 sign-off

- [ ] Product verification: every journey walked (product engineer)
- [ ] Integration review complete (lead engineer)
- [ ] QA verdict PASS (QA engineer)
- [ ] Feature PR opened:
- [ ] Merged by the user
EOF
cat > "$F/qa-report.md" <<'EOF'
# QA report

Verdict: PENDING

## Bugs
| ID | AC ID | Severity | Status | Summary | Evidence |
| --- | --- | --- | --- | --- | --- |
EOF
cat > "$F/questions.md" <<'EOF'
# Questions

| # | From | To | Question | Answer | Status |
| --- | --- | --- | --- | --- | --- |
EOF
printf 'eng-api: B1 done (abc123).\n\n# Feature 02 progress\n' > "$F/progress.md"
git add -A && git commit -q -m init

expect_next "no AC IDs: spec" spec
expect_line "branch: feature branch missing" "feature branch feature/02-orders (missing)"
expect_line "plan: none" "Plan: none"
expect_line "progress: newest note" "Progress: eng-api: B1 done (abc123)."

printf '| AC-02-001 | it works |\n| AC-02-002 | it also works |\n' >> "$F/acceptance-criteria.md"
cat > "$F/dev-plan.md" <<'EOF'
# Dev plan

Status: DRAFT

## Ownership
| Teammate | Owned globs |
| --- | --- |
| eng-api | api/** |
| qa | tests/qa/** |

## Tasks

### lead
- [chore] L0: Contracts commit (LOW)

### eng-api
- [AC-02-001] B1: First (NORMAL)
- [AC-02-002] B2: Second (NORMAL)
  Blocked by: B1
EOF
expect_next "plan DRAFT: plan" plan
expect_line "plan: tasks per owner" "Plan: DRAFT · 3 tasks (lead 1, eng-api 2)"

sed -i 's/^Status: DRAFT/Status: READY/' "$F/dev-plan.md"
git switch -q -c feature/02-orders
expect_next "READY, integration unticked: build" build
expect_line "branch: on it" "Branch: feature/02-orders · feature branch feature/02-orders (on it)"
git switch -q main
expect_line "branch: exists" "feature branch feature/02-orders (exists)"
git switch -q feature/02-orders

sed -i 's/^Status: READY/Status: READY/; s/^- \[AC-02-002\] B2: Second/- [AC-02-002] B1: Second/' "$F/dev-plan.md"
expect_line "plan: a bad label is reported, not fatal" "tasks unreadable (duplicate label B1"
sed -i 's/^- \[AC-02-002\] B1: Second/- [AC-02-002] B2: Second/' "$F/dev-plan.md"

sed -i 's/^- \[ \] Integration review/- [x] Integration review/' "$F/signoff.md"
expect_next "integration ticked, security none: verify" verify
expect_line "signoff line" "Signoff: integration review yes · QA verdict PENDING · product verification no · PR none · merged no"
if state | grep -q '^Security:'; then fail "security none: no Security line"; else ok "security none: no Security line"; fi

# --- security independent ---
printf 'module=shop\nnumber=02\nprofile=full\nsurfaces=api,web-ui\nslug=orders\nsecurity=independent\n' > "$F/.plumbline"
cat > "$F/security.md" <<'EOF'
# Feature 02 security

Independent pass: complete (round 1) - api surface. Web-ui surface not attacked in this pass.

## Own attacks
| SEC ID | Surface | Attack | Must happen |
| --- | --- | --- | --- |

## Findings
| # | Severity | Finding | Status | Evidence |
| --- | --- | --- | --- | --- |
| 1 | medium | Clerk called before the order check | open | SEC-02-040: fail |
EOF
expect_next "independent pass with a surface left: attack" attack
expect_line "security line" 'Security: independent pass "complete (round 1) - api surface. Web-ui surface not attacked in this pass." · findings: #1 medium open'
expect_line "phase line: required parts" "security independent (required: attacks independent)"
sed -i 's/^Independent pass:.*/Independent pass: complete (round 1)/' "$F/security.md"
expect_next "pass complete, medium finding open: past attack" verify
sed -i 's/| 1 | medium | Clerk called before the order check | open |/| 1 | medium | Clerk called before the order check | fixed |/' "$F/security.md"
expect_next "a fixed finding awaits verification: attack" attack
sed -i 's/| fixed |/| verified |/' "$F/security.md"
expect_next "verified: verify" verify
printf '| 2 | high | Another tenant reads an order | open | SEC-02-041: fail |\n' >> "$F/security.md"
expect_next "open high finding: attack" attack
printf '\nRisk accepted: #2 high Another tenant reads an order - demo data only (approved by Safi)\n' >> "$F/security.md"
expect_next "open high finding the user accepted: verify" verify
printf '\nSecurity waived: independent - internal tool (approved by Safi)\n' >> "$F/security.md"
sed -i 's/^Independent pass:.*/Independent pass: in progress (round 2): api; left: web-ui/' "$F/security.md"
expect_next "independent waived: an incomplete pass doesn't hold it" verify

# --- verify ---
sed -i 's/^Verdict: PENDING/Verdict: PASS/' "$F/qa-report.md"
expect_next "QA PASS, product unticked: verify" verify
sed -i 's/^- \[ \] Product verification/- [x] Product verification/' "$F/signoff.md"
expect_next "QA PASS, product ticked: signoff" signoff
printf '| BUG-02-001 | AC-02-001 | high | OPEN | Crash | shot.png |\n' >> "$F/qa-report.md"
expect_next "an open high bug: verify" verify
expect_line "bugs line" "Bugs: BUG-02-001 high open"
sed -i 's/| high | OPEN |/| high | FIXED |/' "$F/qa-report.md"
expect_next "a fixed high bug isn't open: signoff" signoff
expect_line "a fixed bug is still listed for re-test" "Bugs: BUG-02-001 high fixed"
sed -i 's/| high | FIXED |/| high | VERIFIED |/' "$F/qa-report.md"
expect_line "a verified bug isn't listed" "Bugs: none open"

# --- questions ---
cat >> "$F/questions.md" <<'EOF'
| Q1 | product | user | Turn off public sign-up? | | OPEN |
| Q2 | eng-api | lead | Which id? | | OPEN |
| Q3 | qa | product | Copy? | | ESCALATED |
| Q4 | product | user (via lead) | Done? | Yes | ANSWERED |
EOF
expect_line "questions by audience" "Questions: for the user: Q1 · for agents: Q2 (lead) · escalated: Q3"

# --- PR and merge ---
sed -i 's|^- \[ \] Feature PR opened:.*|- [x] Feature PR opened: https://example.com/pr/7|' "$F/signoff.md"
expect_next "PR opened: merge" merge
expect_line "PR link" "PR https://example.com/pr/7"
sed -i 's/^- \[ \] Merged by the user/- [x] Merged by the user/' "$F/signoff.md"
expect_next "merged: done" done

# --- uncommitted files by owner ---
git add -A && git commit -q -m state
mkdir -p api tests/qa other
echo x > api/a.ts; echo y > tests/qa/b.ts; echo z > other/c.txt; echo n >> "$F/progress.md"
expect_line "uncommitted by owner" "Uncommitted: 4 files (by owner: shared 1, eng-api 1, unowned 1, qa 1)"
rm -rf api tests other; git checkout -q -- "$F/progress.md"
expect_line "clean tree" "Uncommitted: none"

# --- the task list ---
mkdir -p "$T/home/.claude/teams/t1" "$T/home/.claude/tasks/t1"
cwd="$T/repo"; command -v cygpath >/dev/null 2>&1 && cwd=$(cygpath -m "$T/repo")
jq -n --arg c "$cwd" --argjson t "$(( $(date +%s) * 1000 ))" '{createdAt: $t, members: [{name: "lead", cwd: $c}, {name: "eng-api", cwd: $c}]}' > "$T/home/.claude/teams/t1/config.json"
jq -n '{id: "1", subject: "[AC-02-001] B1: First", owner: "eng-api", status: "completed", blockedBy: []}' > "$T/home/.claude/tasks/t1/1.json"
jq -n '{id: "2", subject: "[AC-02-002] B2: Second", owner: "eng-api", status: "pending", blockedBy: ["1"]}' > "$T/home/.claude/tasks/t1/2.json"
jq -n '{id: "3", subject: "[chore] L0: Contracts", owner: "lead", status: "in_progress", blockedBy: []}' > "$T/home/.claude/tasks/t1/3.json"
expect_line "task list: open per owner" "Task list: 2 of 3 open (eng-api 1, lead 1)"

# --- read-only ---
before=$(git status --porcelain --untracked-files=all)
state >/dev/null
[[ "$(git status --porcelain --untracked-files=all)" == "$before" ]] && ok "read-only: the tree is unchanged" || fail "read-only: it wrote a file"

echo
echo "$pass passed, $failed failed"
(( failed == 0 ))
