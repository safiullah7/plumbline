#!/usr/bin/env bash
# Self-test for the v0.4b project profile: detect-project.sh on generated fixture
# repos, and the profile helpers in lib.sh (project_surfaces, surface_row, and
# check_command's precedence and adapter mapping, through run_checks). Run from
# the repo root:
#   bash tests/profile-selftest.sh
# Works in bash on macOS and Linux, and in Git Bash on Windows.
set -u
command -v jq >/dev/null 2>&1 || { echo "jq isn't installed or isn't on PATH."; exit 1; }
G="$(cd "$(dirname "${0//\\//}")/.." && pwd)/plugins/plumbline/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tmp"
export HOME="$T" TMPDIR="$T/tmp"
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_DATA PLUMBLINE_HOOK_TIMING
unset PLUMBLINE_TYPECHECK PLUMBLINE_LINT PLUMBLINE_TEST_AC

pass=0; failed=0
ok()   { pass=$((pass+1)); echo "ok    $1"; }
fail() { failed=$((failed+1)); echo "FAIL  $1"; }
assert() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
eq() { # name, got, expected
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (got '$2', expected '$3')"; fi
}
has() { grep -qF -- "$2" <<<"$1"; }   # text, fixed string
# mk <file> <line>...: writes the lines to the file, creating its folders.
mk() { local f="$1"; shift; mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"; }
# detect <repo> [args]: detect-project.sh run in that repo.
detect() { local r="$1"; shift; (cd "$r" && CLAUDE_PROJECT_DIR="$r" bash "$G/detect-project.sh" "$@"); }
# row_of <proposal> <surface>: that surface's table line ("" when there's none).
row_of() { grep -F -- "| $2 |" <<<"$1" | head -n1; }
# surfaces_of <proposal>: the Surface cells, comma-separated.
surfaces_of() {
  awk '/^\| Surface /{ t = 1; next } t && /^\| ---/ { next } t && /^\|/ { s = $0; sub(/^\| /, "", s); sub(/ \|.*/, "", s); print s; next } t { exit }' <<<"$1" \
    | paste -sd, -
}

# --- detection: Node web app ---
R="$T/node-web"
mk "$R/package.json" '{"name":"shop","private":true,"dependencies":{"next":"14.2.0","react":"18.3.1","react-dom":"18.3.1"},' \
  '"scripts":{"dev":"next dev","build":"next build","typecheck":"tsc --noEmit"}}'
mk "$R/package-lock.json" '{}'
mk "$R/node_modules/express/package.json" '{"name":"express","dependencies":{"koa":"1"}}'
mk "$R/dist/package.json" '{"name":"bundle","dependencies":{"express":"4"}}'
out=$(detect "$R"); rc=$?
eq "node web: exit 0" "$rc" 0
eq "node web: one web-ui row with the scripts it has (no lint script, no lint cell)" "$(row_of "$out" web-ui)" \
  "| web-ui | Next.js | ** | npm run dev (http://localhost:3000) | npm run -s typecheck | | node --dir . |"
eq "node web: node_modules and dist are skipped" "$(surfaces_of "$out")" web-ui
assert "node web: proposal keeps the profile header" has "$out" "Confirm: auto"
assert "node web: and the Generic commands section" has "$out" "## Generic commands"
assert "node web: no placeholder rows left" test -z "$(grep -F '| <' <<<"$out")"

# --- detection: Node API + web monorepo, npm workspaces ---
R="$T/mono-npm"
mk "$R/package.json" '{"name":"mono","private":true,"workspaces":["apps/*"],"devDependencies":{"typescript":"5"}}'
mk "$R/package-lock.json" '{}'
mk "$R/apps/web/package.json" '{"name":"@mono/web","dependencies":{"react":"18","react-dom":"18"},"devDependencies":{"vite":"5"},' \
  '"scripts":{"dev":"vite","lint":"eslint ."}}'
mk "$R/apps/api/package.json" '{"name":"@mono/api","dependencies":{"express":"4","@anthropic-ai/sdk":"0.30"},' \
  '"scripts":{"start":"PORT=4100 node server.js","typecheck":"tsc --noEmit","lint":"eslint ."}}'
mk "$R/apps/api/.github/workflows/ci.yml" 'on: push'
out=$(detect "$R")
eq "npm monorepo: surfaces per package, root proposes none" "$(surfaces_of "$out")" "api,web-ui,ai (check)"
eq "npm monorepo: web-ui with npm -w and the vite port" "$(row_of "$out" web-ui)" \
  "| web-ui | React | apps/web/** | npm run dev -w apps/web (http://localhost:5173) | | npm run -s lint -w apps/web | node --dir apps/web |"
eq "npm monorepo: api from express, port from the start script" "$(row_of "$out" api)" \
  "| api | Express | apps/api/** | npm run start -w apps/api (http://localhost:4100) | npm run -s typecheck -w apps/api | npm run -s lint -w apps/api | node --dir apps/api |"
eq "npm monorepo: the Anthropic SDK is an ai (check) row" "$(row_of "$out" "ai (check)")" \
  "| ai (check) | Node (@anthropic-ai/sdk) | apps/api/** | | | | |"

# --- the same monorepo with pnpm-workspace.yaml, and with yarn ---
R="$T/mono-pnpm"
mkdir -p "$R" && cp -R "$T/mono-npm/apps" "$R/"
mk "$R/package.json" '{"name":"mono","private":true}'
mk "$R/pnpm-workspace.yaml" 'packages:' "  - 'apps/*'   # the apps" '  - "!**/test/**"'
out=$(detect "$R")
eq "pnpm monorepo: same surfaces" "$(surfaces_of "$out")" "api,web-ui,ai (check)"
eq "pnpm monorepo: web-ui with pnpm --filter" "$(row_of "$out" web-ui)" \
  "| web-ui | React | apps/web/** | pnpm --filter @mono/web run dev (http://localhost:5173) | | pnpm --filter @mono/web run lint | node --dir apps/web |"
eq "pnpm monorepo: api typecheck with pnpm --filter" "$(row_of "$out" api | awk -F' [|] ' '{ print $5 }')" \
  "pnpm --filter @mono/api run typecheck"
R="$T/mono-yarn"
mkdir -p "$R" && cp -R "$T/mono-npm/apps" "$T/mono-npm/package.json" "$R/" && : > "$R/yarn.lock"
out=$(detect "$R")
assert "yarn monorepo: run and lint with yarn workspace" grep -qF \
  "| yarn workspace @mono/web run dev (http://localhost:5173) | | yarn workspace @mono/web run lint |" <<<"$out"
R="$T/two-webs"
mk "$R/package.json" '{"private":true,"workspaces":["apps/*"]}'
mk "$R/apps/shop/package.json" '{"name":"shop","dependencies":{"next":"14"}}'
mk "$R/apps/admin/package.json" '{"name":"admin","dependencies":{"vue":"3"}}'
out=$(detect "$R")
eq "two web apps: the second gets its folder's name" "$(surfaces_of "$out")" "web-ui,web-ui-shop"

# --- detection: Go API and Go CLI ---
R="$T/go-api"
mk "$R/go.mod" 'module example.com/api' '' 'go 1.22'
mk "$R/cmd/api/main.go" 'package main' '' 'import "net/http"' '' \
  'func main() { http.ListenAndServe(":8080", http.NewServeMux()) }'
mk "$R/internal/store/store.go" 'package store'
mk "$R/.golangci.yml" 'linters: {}'
out=$(detect "$R")
eq "go api: api from cmd/ plus a net/http server" "$(row_of "$out" api)" \
  "| api | Go | ** | go run ./cmd/api | go vet ./... | golangci-lint run | go --dir . |"
eq "go api: nothing else" "$(surfaces_of "$out")" api
R="$T/go-cli"
mk "$R/go.mod" 'module example.com/tool' '' 'go 1.22' '' 'require github.com/sashabaranov/go-openai v1.20.0'
mk "$R/cmd/tool/main.go" 'package main' '' 'import (' '  "flag"' '  "net/http"' ')' '' \
  'func main() { flag.Parse(); http.Get("https://example.com") }'
out=$(detect "$R")
eq "go cli: an HTTP client alone is still a cli" "$(row_of "$out" cli)" \
  "| cli | Go | ** | go run ./cmd/tool | go vet ./... | | go --dir . |"
eq "go cli: go-openai is an ai (check) row" "$(surfaces_of "$out")" "cli,ai (check)"
R="$T/go-nested"
mk "$R/services/api/go.mod" 'module example.com/api'
mk "$R/services/api/main.go" 'package main' 'import "github.com/go-chi/chi/v5"' 'func main() { _ = chi.NewRouter() }'
out=$(detect "$R")
eq "go nested module: a router import, commands run in its folder" "$(row_of "$out" api)" \
  "| api | Go | services/api/** | cd services/api && go run . | cd services/api && go vet ./... | | go --dir services/api |"

# --- detection: Python FastAPI (CRLF pyproject) ---
R="$T/py-api"
mk "$R/pyproject.toml" '[project]' 'name = "clinic-api"' 'description = "Not a Flask app"' 'dependencies = [' \
  '    "fastapi[standard]>=0.110",  # web' "    'uvicorn>=0.29'," '    "openai>=1.0",' ']' '' \
  '[project.optional-dependencies]' 'dev = ["pytest>=8", "ruff"]' '' '[tool.ruff]' 'line-length = 100'
sed 's/$/\r/' "$R/pyproject.toml" > "$R/p.tmp" && mv "$R/p.tmp" "$R/pyproject.toml"
mk "$R/app/main.py" 'from fastapi import FastAPI' '' 'app = FastAPI()'
mk "$R/.venv/lib/site-packages/flask/pyproject.toml" '[project]' 'dependencies = ["django"]'
mk "$R/migrations/001_init.sql" 'create table x (id int);'
mk "$R/db/migrations/002.sql" 'select 1;'
mk "$R/.github/workflows/deploy.yml" 'on: push'
out=$(detect "$R")
eq "python fastapi: api row with uvicorn and ruff" "$(row_of "$out" api)" \
  "| api | FastAPI | ** | uvicorn app.main:app --reload (http://localhost:8000) | | ruff check . | pytest --dir . |"
eq "python fastapi: the openai dependency is an ai (check) row" "$(row_of "$out" "ai (check)")" \
  "| ai (check) | Python (openai) | ** | | | | |"
eq "negative: workflows and migration .sql propose no infra or data, .venv skipped" "$(surfaces_of "$out")" "api,ai (check)"
R="$T/py-cli"
mk "$R/tools/pyproject.toml" '[project]' 'name = "tool"' 'dependencies = ["click"]' '' '[project.scripts]' 'tool = "tool:main"'
mk "$R/lib/setup.py" 'from setuptools import setup'
mk "$R/docs/requirements.txt" 'mkdocs==1.6'
mk "$R/svc/requirements-prod.txt" '# deps' 'Django==5.0' 'anthropic'
out=$(detect "$R")
eq "python: [project.scripts] is a cli, setup.py a library, a docs requirements file nothing" \
  "$(surfaces_of "$out")" "library,api,cli,ai (check)"
eq "python: requirements-only Django api runs in its folder" "$(row_of "$out" api)" \
  "| api | Django | svc/** | | | | pytest --dir svc |"
R="$T/py-poetry"
mk "$R/pyproject.toml" '[tool.poetry]' 'name = "x"' '' '[tool.poetry.dependencies]' 'python = "^3.11"' 'Flask = "^3.0"' \
  'llama_index = "*"' '' '[tool.mypy]' 'strict = true'
out=$(detect "$R")
eq "python poetry: Flask api with mypy" "$(row_of "$out" api)" "| api | Flask | ** | | mypy . | | pytest --dir . |"
eq "python poetry: llama_index is an ai (check) row" "$(row_of "$out" "ai (check)")" \
  "| ai (check) | Python (llama-index) | ** | | | | |"

# --- detection: Flutter, Rust, and the other hints ---
R="$T/flutter"
mk "$R/pubspec.yaml" 'name: app' 'environment:' '  sdk: ">=3.0.0 <4.0.0"' 'dependencies:' '  flutter:' '    sdk: flutter' \
  '  http: ^1.2.0' 'dev_dependencies:' '  flutter_test:' '    sdk: flutter' 'flutter:' '  uses-material-design: true'
mk "$R/ios/Runner.xcodeproj/project.pbxproj" 'x'
mk "$R/android/build.gradle" 'x'
mk "$R/build/app/pubspec.yaml" 'name: junk'
out=$(detect "$R")
eq "flutter: mobile-ui row" "$(row_of "$out" mobile-ui)" "| mobile-ui | Flutter | ** | flutter run | flutter analyze | | |"
eq "flutter: its ios/ and android/ folders aren't a separate hint" "$(surfaces_of "$out")" mobile-ui
R="$T/react-native"
mk "$R/package.json" '{"name":"app","dependencies":{"react":"18","react-native":"0.74"}}'
mk "$R/ios/Podfile" 'x'
mk "$R/android/build.gradle" 'x'
mk "$R/node_modules/lib/ios/Podfile" 'x'
out=$(detect "$R")
eq "react native: no web-ui, one mobile-ui (check) row" "$(surfaces_of "$out")" "mobile-ui (check)"
eq "react native: with its native folders" "$(row_of "$out" "mobile-ui (check)")" \
  "| mobile-ui (check) | React Native, Android, iOS | ** android/** ios/** | | | | |"
R="$T/dart-only"
mk "$R/pubspec.yaml" 'name: tool' 'dependencies:' '  args: ^2.0.0'
eq "dart without the Flutter SDK proposes nothing" "$(surfaces_of "$(detect "$R")")" ""
R="$T/hints"
mk "$R/main.tf" 'terraform {}'
mk "$R/helm/Chart.yaml" 'name: x'
mk "$R/analytics/dbt_project.yml" 'name: x'
mk "$R/dags/etl.py" 'x'
mk "$R/mobile/ios/Podfile" 'x'
mk "$R/mobile/android/settings.gradle" 'x'
mk "$R/desk/package.json" '{"name":"desk","devDependencies":{"electron":"30"}}'
mk "$R/cli/Cargo.toml" '[package]' 'name = "x"' '' '[[bin]]' 'name = "x"'
mk "$R/core/Cargo.toml" '[package]' 'name = "core"' '' '[lib]' 'path = "src/lib.rs"'
mk "$R/Cargo.toml" '[workspace]' 'members = ["cli", "core"]'
out=$(detect "$R")
eq "hints and rust: every row" "$(surfaces_of "$out")" \
  "cli,library,data (check),desktop-ui (check),mobile-ui (check),infra (check)"
eq "hints: dbt and the dags folder share one data row" "$(row_of "$out" "data (check)")" \
  "| data (check) | Airflow, dbt | dags/** analytics/** | | | | |"
eq "hints: infra from root .tf and helm/" "$(row_of "$out" "infra (check)")" \
  "| infra (check) | Terraform, Helm | *.tf helm/** | | | | |"
eq "hints: native app folders" "$(row_of "$out" "mobile-ui (check)")" \
  "| mobile-ui (check) | Android, iOS | mobile/android/** mobile/ios/** | | | | |"
eq "rust: a [[bin]] is a cli with cargo commands in its folder" "$(row_of "$out" cli)" \
  "| cli | Rust | cli/** | cd cli && cargo run | cd cli && cargo check | cd cli && cargo clippy | |"

# --- --write ---
R="$T/node-web"
proposal=$(detect "$R")
out=$(detect "$R" --write); rc=$?
eq "--write: exit 0 and says so" "$rc/$out" "0/detect-project: wrote docs/product/project.md"
eq "--write: writes the printed proposal" "$(cat "$R/docs/product/project.md")" "$proposal"
mk "$R/docs/product/project.md" '# my profile'
out=$(detect "$R" --write); rc=$?
eq "--write: an existing project.md is never overwritten" "$(cat "$R/docs/product/project.md")" "# my profile"
eq "--write: ...exit 0 with a message" "$rc/$out" "0/detect-project: docs/product/project.md already exists; left unchanged."
detect "$R" --bogus >/dev/null 2>&1; rc=$?
eq "usage: an unknown argument exits 2" "$rc" 2

# --- lib.sh: project_surfaces, surface_row, check_command ---
P="$T/profiled"
mkdir -p "$P/docs/product"
{
  printf '%s\r\n' '# Project profile' '' 'Confirm: auto' '' '## Surfaces' \
    '| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |' \
    '| --- | --- | --- | --- | --- | --- | --- |' \
    '| web-ui | Next.js | apps/web/** | npm run dev -w apps/web | npm run -s typecheck -w apps/web | | node --dir apps/web |' \
    '| api | Go | services/api/** | go run ./cmd/api | go vet ./... | `golangci-lint run` | go --dir services/api |' \
    '| cli | Rust | cli/** | cargo run | cargo check | cargo clippy | generic |' \
    '| tool | Make | tools/** | | | | make ac -- |' \
    '| lib | Python | lib/** | | | | pytest |' \
    '' '## Generic commands' '### cli' '```' 'cargo test -- {ids_underscored}' '```' \
    '' '## Notes' '| Surface | Other |' '| --- | --- |' '| stray | not a surface |'
} > "$P/docs/product/project.md"
# lib <repo> <command...>: runs in a fresh shell with lib.sh sourced for that repo.
lib() { local r="$1"; shift; (cd "$r" && export CLAUDE_PROJECT_DIR="$r" && source "$G/lib.sh" && "$@"); }
S=$(cd "$G" && pwd)   # PLUMBLINE_SCRIPTS as lib.sh spells it

eq "project_surfaces: one per line, only the Surfaces table, CRLF stripped" \
  "$(lib "$P" project_surfaces | paste -sd, -)" "web-ui,api,cli,tool,lib"
eq "surface_row: tab-separated cells" "$(lib "$P" surface_row api | tr '\t' '#')" \
  'api#Go#services/api/**#go run ./cmd/api#go vet ./...#`golangci-lint run`#go --dir services/api'
lib "$P" surface_row mobile-ui >/dev/null; rc=$?
eq "surface_row: an unknown surface returns 1" "$rc" 1
lib "$P" surface_row "" >/dev/null; rc=$?
eq "surface_row: no surface returns 1" "$rc" 1
lib "$T/go-api" surface_row api >/dev/null; rc=$?
eq "surface_row: no project.md returns 1" "$rc" 1
eq "project_surfaces: no project.md prints nothing" "$(lib "$T/go-api" project_surfaces)" ""

cc() { lib "$P" check_command "$@"; }
eq "check_command: the surface's Typecheck cell" "$(cc PLUMBLINE_TYPECHECK api 'npm run -s typecheck')" "go vet ./..."
eq "check_command: a cell in backticks is unwrapped" "$(cc PLUMBLINE_LINT api 'npm run -s lint')" "golangci-lint run"
out=$(cc PLUMBLINE_LINT web-ui 'npm run -s lint'); rc=$?
eq "check_command: an empty cell skips the check" "$rc/$out" "0/"
eq "check_command: node adapter with its arguments" "$(cc PLUMBLINE_TEST_AC web-ui x)" "bash \"$S/ac-tests/node.sh\" --dir apps/web"
eq "check_command: go adapter" "$(cc PLUMBLINE_TEST_AC api x)" "bash \"$S/ac-tests/go.sh\" --dir services/api"
eq "check_command: pytest adapter without arguments" "$(cc PLUMBLINE_TEST_AC lib x)" "bash \"$S/ac-tests/pytest.sh\""
eq "check_command: generic adds --surface" "$(cc PLUMBLINE_TEST_AC cli x)" "bash \"$S/ac-tests/generic.sh\" --surface cli"
eq "check_command: any other AC cell is a raw command" "$(cc PLUMBLINE_TEST_AC tool x)" "make ac --"
eq "check_command: an unknown surface uses the legacy default" "$(cc PLUMBLINE_TEST_AC mobile-ui 'npm run -s test:ac --')" \
  "npm run -s test:ac --"
eq "check_command: no surface and several rows uses the legacy default" "$(cc PLUMBLINE_TYPECHECK '' 'npm run -s typecheck')" \
  "npm run -s typecheck"
eq "check_command: an unknown env var name uses the default" "$(cc PLUMBLINE_OTHER api dflt)" dflt
eq "check_command: env var wins over the profile" "$(PLUMBLINE_TYPECHECK=true cc PLUMBLINE_TYPECHECK api x)" true
out=$(PLUMBLINE_TEST_AC="" cc PLUMBLINE_TEST_AC api x); rc=$?
eq "check_command: env var set to \"\" still skips" "$rc/$out" "0/"
eq "check_command: no project.md keeps the v0.3 default" \
  "$(lib "$T/go-api" check_command PLUMBLINE_TEST_AC api 'npm run -s test:ac --')" "npm run -s test:ac --"
eq "check_command: no project.md, no surface" \
  "$(lib "$T/go-api" check_command PLUMBLINE_LINT '' 'npm run -s lint')" "npm run -s lint"
P1="$T/single"
mk "$P1/docs/product/project.md" '## Surfaces' '| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |' \
  '| --- | --- | --- | --- | --- | --- | --- |' '| api | Go | ** | | go vet ./... | | go --dir . |'
eq "check_command: no surface and a single row uses that row" \
  "$(lib "$P1" check_command PLUMBLINE_TYPECHECK '' 'npm run -s typecheck')" "go vet ./..."
eq "check_command: ...and its empty Lint cell skips" "$(lib "$P1" check_command PLUMBLINE_LINT '' 'npm run -s lint')" ""
eq "check_command: a named surface missing from a one-row profile uses the default" \
  "$(lib "$P1" check_command PLUMBLINE_LINT web-ui 'npm run -s lint')" "npm run -s lint"

# --- run_checks through the adapters, from a scripts folder with a space and a quote ---
D="$T/plug in's \$HOME/scripts"
mkdir -p "$D/ac-tests"
cp "$G/lib.sh" "$D/"
for a in node go generic; do
  mk "$D/ac-tests/$a.sh" '#!/usr/bin/env bash' "echo \"$a.sh [\$*] in \$(basename \"\$PWD\")\""
done
mk "$P/docs/product/project.md" '## Surfaces' '| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |' \
  '| --- | --- | --- | --- | --- | --- | --- |' \
  '| web-ui | Next.js | apps/web/** | | true | | node --dir apps/web |' \
  '| api | Go | services/api/** | | | false | go --dir services/api |' \
  '| cli | Rust | ** | | | | generic |'
rc_of() { # surface: run_checks with the copied lib.sh, then the AC test's output
  (cd "$T" && export CLAUDE_PROJECT_DIR="$P" && source "$D/lib.sh" && run_checks "AC-01-001|AC-01-002" "$1"
   echo "rc=$?/$RUN_CHECKS_FAILED"; cat "$RUN_CHECKS_LOG"; rm -f "$RUN_CHECKS_LOG")
}
out=$(rc_of web-ui)
eq "run_checks: web-ui runs the node adapter, IDs last, in the repo root" "$out" \
  "rc=0/"$'\n'"node.sh [--dir apps/web AC-01-001|AC-01-002] in profiled"
out=$(rc_of api)
eq "run_checks: api's Lint cell fails before its tests" "$(head -n1 <<<"$out")" "rc=1/lint"
out=$(PLUMBLINE_LINT="" rc_of api)
eq "run_checks: env var overrides that cell, then the go adapter runs" "$(tail -n1 <<<"$out")" \
  "go.sh [--dir services/api AC-01-001|AC-01-002] in profiled"
out=$(rc_of cli)
eq "run_checks: generic gets --surface and the IDs" "$(tail -n1 <<<"$out")" \
  "generic.sh [--surface cli AC-01-001|AC-01-002] in profiled"
out=$(PLUMBLINE_TEST_AC="echo raw" rc_of web-ui)
eq "run_checks: PLUMBLINE_TEST_AC still wins" "$(tail -n1 <<<"$out")" "raw AC-01-001|AC-01-002"

for s in web-ui:web-ui web-ui-shop:web-ui api:api api-billing:api ai:ai ai-chat:ai mobile-ui:mobile-ui data:data; do
  eq "surface_kind: ${s%%:*} is ${s#*:}" "$(lib "$P" surface_kind "${s%%:*}")" "${s#*:}"
done
for s in tool lib web apis "" ui; do
  lib "$P" surface_kind "$s" >/dev/null; rc=$?
  eq "surface_kind: '$s' isn't a surface (exit 1)" "$rc" 1
done

echo
echo "$pass passed, $failed failed"
[[ $failed -eq 0 ]]
