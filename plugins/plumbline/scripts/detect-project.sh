#!/usr/bin/env bash
# Proposes docs/product/project.md, the project profile (dev plan §6.3), from the
# repo's manifests. A proposal only: the build and kickoff skills show it and ask
# the user to confirm or edit it.
#   detect-project.sh [--write]
# Package groups are the root plus every folder with a manifest (package.json,
# pyproject.toml, setup.py, requirements*.txt, go.mod, Cargo.toml, pubspec.yaml,
# dbt_project.yml), skipping dependency and build folders. Every signal is applied
# to every group, so one group can propose several surfaces. Weak signals (LLM
# SDKs, dbt or Airflow, Terraform, Helm or Kubernetes at the root, native app
# folders, Electron, Tauri, React Native) become rows whose Surface ends in
# " (check)", for the user to keep or delete. CI workflows and SQL migrations are
# never signals. Commands are proposed only when that package defines them (a
# package.json script, a tool's config); every other cell is left blank.
# Prints the proposal. With --write it writes docs/product/project.md instead,
# only when that file doesn't exist yet. Exit 0, or 1 without jq, 2 on usage.
source "$(dirname "${0//\\//}")/lib.sh"
usage() { echo "usage: detect-project.sh [--write]" >&2; exit 2; }

write=""
case "$#/${1:-}" in
  0/) ;;
  1/--write) write=1 ;;
  *) usage ;;
esac
command -v jq >/dev/null 2>&1 || { echo "detect-project: jq isn't installed or isn't on PATH." >&2; exit 1; }
cd "$PROJECT_DIR" || exit 1
TEMPLATE="$PLUMBLINE_SCRIPTS/../skills/kickoff/templates/project.md"

# --- helpers ---

# A folder for a command line: as is when it's plain, else single-quoted.
qdir() {
  if [[ "$1" =~ ^[A-Za-z0-9._/@+-]+$ ]]; then printf '%s' "$1"
  else printf "'%s'" "${1//\'/\'\\\'\'}"; fi
}
# "cd <group> && " for a group below the root, so a command runs in its package.
in_dir() { [[ "$1" == . ]] || printf 'cd %s && ' "$(qdir "$1")"; }
# A group's folder as a path prefix ("" for the root), and its Paths cell.
prefix_of() { [[ "$1" == . ]] || printf '%s/' "$1"; }
paths_of() { printf '%s**' "$(prefix_of "$1")"; }
# True if any of the paths exists (an unmatched glob stays as written).
any_exists() { local f; for f in "$@"; do [[ -e "$f" ]] && return 0; done; return 1; }
# True if a newline-separated list holds the exact line.
listed() { grep -qxF -- "$2" <<<"$1"; }
# The first name from a space-separated list that the list of lines holds.
first_listed() { local n; for n in $2; do listed "$1" "$n" && { printf '%s' "$n"; return 0; }; done; return 1; }

ROWS="" HINTS=""
# row <surface> <stack> <paths> <run> <typecheck> <lint> <AC tests>
row() {
  local IFS=$'\t' line
  line="$*"; line="${line//|//}"   # cells never contain a |
  if [[ "$1" == *" (check)" ]]; then HINTS="$HINTS$line"$'\n'; else ROWS="$ROWS$line"$'\n'; fi
}
hint() { row "$1 (check)" "$2" "$3" "" "" "" ""; }   # surface, stack, paths

# --- package groups ---

manifests=$(find . -type d \( -name node_modules -o -name .git -o -name vendor -o -name dist \
    -o -name build -o -name target -o -name .venv -o -name venv -o -name .next -o -name .dart_tool \) -prune \
  -o -type f \( -name package.json -o -name pyproject.toml -o -name setup.py -o -name 'requirements*.txt' \
    -o -name go.mod -o -name Cargo.toml -o -name pubspec.yaml -o -name dbt_project.yml \) -print 2>/dev/null \
  | tr -d '\r')
groups=$( { echo .; while IFS= read -r m; do [[ -n "$m" ]] || continue; m="${m%/*}"; m="${m#./}"
            [[ "$m" == . || -z "$m" ]] || echo "$m"; done <<<"$manifests"; } | awk '!seen[$0]++' \
          | { read -r root; echo "$root"; LC_ALL=C sort; })
go_groups=$(while IFS= read -r g; do [[ -f "$g/go.mod" ]] && echo "$g"; done <<<"$groups")

# Workspace globs from the root package.json and pnpm-workspace.yaml.
ws_globs=""
[[ -f package.json ]] && ws_globs=$(jqr '.workspaces | if type == "array" then .[]
  elif type == "object" then (.packages // [])[] else empty end' package.json 2>/dev/null)
if [[ -f pnpm-workspace.yaml ]]; then
  ws_globs="$ws_globs"$'\n'$(awk -v q="'" '{ sub(/\r$/, "") } /^[^ \t#-]/ { p = ($0 ~ /^packages:/); next }
    p && /^[ \t]*-/ { sub(/^[ \t]*-[ \t]*/, ""); sub(/[ \t]+#.*/, ""); gsub(/"/, ""); gsub(q, ""); print }' \
    pnpm-workspace.yaml)
fi
ws_member() { # group: true if a workspace glob takes it
  local gl
  [[ "$1" != . ]] || return 1
  while IFS= read -r gl; do
    gl="${gl#./}"; gl="${gl%/}"
    [[ -n "$gl" && "$gl" != '!'* ]] || continue
    [[ "$1" == $gl ]] && return 0
  done <<<"$ws_globs"
  return 1
}

# --- Node: signals 1 and 2, Electron, Tauri and React Native hints ---

node_pm() { # group: npm, pnpm or yarn, from the nearest lockfile
  local d
  for d in "$1" .; do
    [[ -f "$d/pnpm-lock.yaml" ]] && { echo pnpm; return; }
    [[ -f "$d/yarn.lock" ]] && { echo yarn; return; }
    [[ -f "$d/package-lock.json" ]] && { echo npm; return; }
  done
  [[ -f pnpm-workspace.yaml ]] && { echo pnpm; return; }
  echo npm
}

# node_script <group> <pm> <package name> <script> <silent: 1 or "">
node_script() {
  local g="$1" pm="$2" name="$3" s="$4" quiet=""
  [[ -n "$5" && "$pm" == npm ]] && quiet="-s "
  if ws_member "$g"; then
    case "$pm" in
      npm)  printf 'npm run %s%s -w %s' "$quiet" "$s" "$(qdir "$g")" ;;
      pnpm) printf 'pnpm --filter %s run %s' "${name:-./$(qdir "$g")}" "$s" ;;
      yarn) if [[ -n "$name" ]]; then printf 'yarn workspace %s run %s' "$name" "$s"
            else printf '%syarn run %s' "$(in_dir "$g")" "$s"; fi ;;
    esac
  else
    printf '%s%s run %s%s' "$(in_dir "$g")" "$pm" "$quiet" "$s"
  fi
}

# The URL a dev script serves on: its --port, -p or PORT=, else the framework's default.
node_url() { # script text, stack
  local re='(--port|-p)[ =]+([0-9]+)'
  if [[ "$1" =~ $re ]]; then echo "http://localhost:${BASH_REMATCH[2]}"; return; fi
  re='PORT=([0-9]+)'
  if [[ "$1" =~ $re ]]; then echo "http://localhost:${BASH_REMATCH[1]}"; return; fi
  case "$2/$1" in
    Next.js/*|Nuxt/*) echo http://localhost:3000 ;;
    */*"ng serve"*) echo http://localhost:4200 ;;
    */*vite*) echo http://localhost:5173 ;;
  esac
}

node_group() { # group
  local g="$1" pj="$1/package.json" deps all scripts name pm stack s tc="" lint="" ac
  deps=$(jqr '(.dependencies // {}) | keys[]' "$pj" 2>/dev/null)
  all=$(jqr '[(.dependencies // {}), (.devDependencies // {})] | add | keys[]' "$pj" 2>/dev/null)
  scripts=$(jqr '(.scripts // {}) | keys[]' "$pj" 2>/dev/null)
  name=$(jqr '.name // empty' "$pj" 2>/dev/null)
  pm=$(node_pm "$g")
  script_text() { jqr --arg s "$1" '.scripts[$s] // empty' "$pj" 2>/dev/null; }
  # Typecheck, lint and run commands, from the scripts this package has.
  s=$(first_listed "$scripts" "typecheck type-check") && tc=$(node_script "$g" "$pm" "$name" "$s" 1)
  listed "$scripts" lint && lint=$(node_script "$g" "$pm" "$name" lint 1)
  ac="node --dir $(qdir "$g")"
  # Engineers write e2e tests named after the criteria too: run them as well.
  listed "$all" "@playwright/test" && ac="$ac + playwright --dir $(qdir "$g")"
  dev_run() { # stack
    local s url
    s=$(first_listed "$scripts" "dev start") || return 0
    url=$(node_url "$(script_text "$s")" "$1")
    printf '%s%s' "$(node_script "$g" "$pm" "$name" "$s" "")" "${url:+ ($url)}"
  }
  # 1. web-ui. React counts only outside React Native.
  local web="next:Next.js nuxt:Nuxt @angular/core:Angular angular:Angular @sveltejs/kit:SvelteKit svelte:Svelte vue:Vue solid-js:Solid"
  listed "$all" react-native || web="$web react:React"
  stack=""
  for s in $web; do listed "$all" "${s%%:*}" && { stack="${s#*:}"; break; }; done
  [[ -n "$stack" ]] && row web-ui "$stack" "$(paths_of "$g")" "$(dev_run "$stack")" "$tc" "$lint" "$ac"
  # 2. api, from runtime dependencies only.
  stack=""
  for s in express:Express fastify:Fastify @nestjs/core:NestJS hono:Hono koa:Koa; do
    listed "$deps" "${s%%:*}" && { stack="${s#*:}"; break; }
  done
  [[ -n "$stack" ]] && row api "$stack" "$(paths_of "$g")" "$(dev_run "$stack")" "$tc" "$lint" "$ac"
  # Hints.
  s=$(grep -xE '@anthropic-ai/sdk|openai|langchain|@langchain/.*|llamaindex|llama-index' <<<"$deps" | paste -sd, - | sed 's/,/, /g')
  [[ -n "$s" ]] && hint ai "Node ($s)" "$(paths_of "$g")"
  listed "$all" electron && hint desktop-ui Electron "$(paths_of "$g")"
  grep -qE '^@tauri-apps/' <<<"$all" && hint desktop-ui Tauri "$(paths_of "$g")"
  if listed "$all" expo; then hint mobile-ui Expo "$(paths_of "$g")"
  elif listed "$all" react-native; then hint mobile-ui "React Native" "$(paths_of "$g")"; fi
}

# --- Python: signal 3 and the LLM hint ---

py_deps() { # group: dependency names, lowercased, with _ and . as -
  local g="$1" f
  {
    [[ -f "$g/pyproject.toml" ]] && awk -v q="'" '
      {
        sub(/\r$/, ""); line = $0; gsub(q, "\"", line)
        sub(/^[ \t]*#.*/, "", line); sub(/[ \t]#.*/, "", line)   # comments, not a URL #fragment
      }
      !arr && line ~ /^[ \t]*\[/ { sec = line; gsub(/[ \t]/, "", sec); gsub(/^\[+|\]+$/, "", sec); next }
      sec ~ /^tool\.poetry\./ && sec ~ /dependencies$/ {
        if (match(line, /^[ \t]*[A-Za-z0-9_.-]+[ \t]*=/)) {
          k = substr(line, RSTART, RLENGTH); gsub(/[ \t=]/, "", k); print k
        }
        next
      }
      (sec == "project" && line ~ /^[ \t]*dependencies[ \t]*=/) ||
        ((sec == "project.optional-dependencies" || sec == "dependency-groups") && line ~ /=/) { arr = 1 }
      arr {
        rest = line
        while (match(rest, /"[^"]*"/)) {
          s = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
          if (match(s, /^[A-Za-z0-9_.-]+/)) print substr(s, 1, RLENGTH)
        }
        bare = line; gsub(/"[^"]*"/, "", bare)
        if (bare ~ /\]/) arr = 0
      }' "$g/pyproject.toml"
    for f in "$g"/requirements*.txt; do
      [[ -f "$f" ]] && awk '{ sub(/\r$/, ""); sub(/^[ \t]+/, "") } /^[#-]/ || $0 == "" { next }
        match($0, /^[A-Za-z0-9_.-]+/) { print substr($0, 1, RLENGTH) }' "$f"
    done
  } | tr 'A-Z' 'a-z' | sed 's/[_.]/-/g' | LC_ALL=C sort -u
}

python_group() { # group
  local g="$1" deps stack="" kind="" tc="" lint="" run="" app py="$1/pyproject.toml" s
  deps=$(py_deps "$g")
  pyconf() { [[ -f "$py" ]] && grep -qE "$1" "$py"; }
  if pyconf '^\[tool\.mypy\]' || [[ -f "$g/mypy.ini" || -f "$g/.mypy.ini" ]]; then tc="$(in_dir "$g")mypy ."
  elif pyconf '^\[tool\.pyright\]' || [[ -f "$g/pyrightconfig.json" ]]; then tc="$(in_dir "$g")pyright"; fi
  if pyconf '^\[tool\.ruff' || [[ -f "$g/ruff.toml" || -f "$g/.ruff.toml" ]]; then lint="$(in_dir "$g")ruff check ."
  elif [[ -f "$g/.flake8" ]]; then lint="$(in_dir "$g")flake8"; fi
  for s in fastapi:FastAPI flask:Flask django:Django; do
    listed "$deps" "${s%%:*}" && { stack="${s#*:}"; break; }
  done
  if [[ -n "$stack" ]]; then
    kind=api
    if [[ "$stack" == FastAPI ]] && listed "$deps" uvicorn; then
      # The first module that creates the app: app/main.py with "app = FastAPI(" -> app.main:app.
      app=$(cd "$g" && find . -type d \( -name .venv -o -name venv -o -name node_modules -o -name .git \
              -o -name build -o -name dist \) -prune \
              -o -type f -name '*.py' -print 2>/dev/null | tr -d '\r' | LC_ALL=C sort \
            | while IFS= read -r f; do
                v=$(grep -m1 -oE '^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*FastAPI\(' "$f" 2>/dev/null) || continue
                f="${f#./}"; f="${f%.py}"; printf '%s:%s\n' "${f//\//.}" "${v%%[ =]*}"; break
              done)
      [[ -n "$app" ]] && run="$(in_dir "$g")uvicorn $app --reload (http://localhost:8000)"
    elif [[ "$stack" == Django && -f "$g/manage.py" ]]; then
      run="$(in_dir "$g")python manage.py runserver (http://localhost:8000)"
    fi
  elif pyconf '^\[(project\.scripts|tool\.poetry\.scripts)\]'; then
    kind=cli stack=Python
  elif [[ -f "$py" || -f "$g/setup.py" ]]; then
    kind=library stack=Python   # a folder with only a requirements file proposes nothing
  fi
  [[ -n "$kind" ]] && row "$kind" "$stack" "$(paths_of "$g")" "$run" "$tc" "$lint" "pytest --dir $(qdir "$g")"
  s=$(grep -xE 'anthropic|openai|langchain(-.*)?|llama-index(-.*)?' <<<"$deps" | paste -sd, - | sed 's/,/, /g')
  [[ -n "$s" ]] && hint ai "Python ($s)" "$(paths_of "$g")"
}

# --- Go: signal 4 and the LLM hint ---

go_files() { # group: its non-test .go files, not those of a nested module
  local g="$1"
  find "$g" \( -type d \( -name vendor -o -name testdata -o -name node_modules -o -name .git \) \) -prune \
    -o -type f -name '*.go' ! -name '*_test.go' -print 2>/dev/null | tr -d '\r' | sed 's#^\./##' \
  | GO_GROUPS="$go_groups" awk -v g="$g" '
      BEGIN { n = split(ENVIRON["GO_GROUPS"], d, "\n") }
      {
        own = "."; best = 0
        for (i = 1; i <= n; i++)
          if (d[i] != "." && index($0, d[i] "/") == 1 && length(d[i]) > best) { own = d[i]; best = length(d[i]) }
        if (own == g) print
      }'
}

go_group() { # group
  local g="$1" files mains="" kind=library server="" run="" lint="" cmds s
  files=$(go_files "$g")
  if [[ -n "$files" ]]; then
    mains=$(tr '\n' '\0' <<<"$files" | xargs -0 grep -lE '^package main([[:space:]]|$)' 2>/dev/null | tr -d '\r')
    server=$(tr '\n' '\0' <<<"$files" | xargs -0 grep -lE \
      '"(github\.com/(gin-gonic/gin|labstack/echo[^"]*|go-chi/chi[^"]*|gorilla/mux|gofiber/fiber[^"]*|julienschmidt/httprouter)|google\.golang\.org/grpc|connectrpc\.com/connect)"|http\.(ListenAndServe|ListenAndServeTLS|NewServeMux|HandleFunc|Handle)\(|http\.Server\{' \
      2>/dev/null | head -n1)
  fi
  # A program: a cmd/ folder, or a main package in the module's own folder.
  if [[ -d "$g/cmd" ]] || awk -v g="$g" '
       $0 == "" { next } { d = $0; if (!sub(/\/[^\/]*$/, "", d)) d = "." } d == g { f = 1 }
       END { exit !f }' <<<"$mains"; then
    if [[ -n "$server" ]]; then kind=api; else kind=cli; fi
    cmds=$(cd "$g" && for s in cmd/*/; do [[ -d "$s" ]] && echo "${s%/}"; done)
    if [[ -n "$cmds" && "$cmds" != *$'\n'* ]]; then run="$(in_dir "$g")go run ./$cmds"
    elif [[ -z "$cmds" ]]; then run="$(in_dir "$g")go run ."; fi
  fi
  for s in "$g" .; do
    any_exists "$s"/.golangci.* && { lint="$(in_dir "$g")golangci-lint run"; break; }
  done
  row "$kind" Go "$(paths_of "$g")" "$run" "$(in_dir "$g")go vet ./..." "$lint" "go --dir $(qdir "$g")"
  s=$(grep -oE 'github\.com/(anthropics/anthropic-sdk-go|openai/openai-go|sashabaranov/go-openai|tmc/langchaingo)' \
        "$g/go.mod" 2>/dev/null | LC_ALL=C sort -u | sed 's#.*/##' | paste -sd, - | sed 's/,/, /g')
  [[ -n "$s" ]] && hint ai "Go ($s)" "$(paths_of "$g")"
}

# --- Rust: signal 6 ---

rust_group() { # group
  local g="$1" ct="$1/Cargo.toml" kind="" s
  grep -qE '^\[package\]' "$ct" 2>/dev/null || return 0   # a workspace root only
  if [[ "${g##*/}" == src-tauri || -f "$g/tauri.conf.json" ]]; then
    hint desktop-ui Tauri "$(paths_of "$g")"; return 0
  fi
  if grep -qE '^\[\[bin\]\]' "$ct" || [[ -f "$g/src/main.rs" ]]; then kind=cli
  elif grep -qE '^\[lib\]' "$ct" || [[ -f "$g/src/lib.rs" ]]; then kind=library; fi
  local run=""; [[ "$kind" == cli ]] && run="$(in_dir "$g")cargo run"
  [[ -n "$kind" ]] && row "$kind" Rust "$(paths_of "$g")" "$run" "$(in_dir "$g")cargo check" "$(in_dir "$g")cargo clippy" ""
  s=$(grep -oE '^(async-openai|openai[A-Za-z0-9_-]*|anthropic[A-Za-z0-9_-]*|langchain-rust)[[:space:]]*=' "$ct" \
        | sed 's/[[:space:]]*=$//' | paste -sd, - | sed 's/,/, /g')
  [[ -n "$s" ]] && hint ai "Rust ($s)" "$(paths_of "$g")"
}

# --- Flutter: signal 5 ---

is_flutter() { # group: pubspec.yaml lists the Flutter SDK under dependencies
  [[ -f "$1/pubspec.yaml" ]] && awk '{ sub(/\r$/, "") } /^[^ \t#]/ { dep = ($0 ~ /^dependencies:/); next }
    dep && /^[ \t]+sdk:[ \t]*flutter[ \t]*$/ { found = 1 } END { exit !found }' "$1/pubspec.yaml"
}

# --- every group ---

while IFS= read -r g; do
  [[ -f "$g/package.json" ]] && node_group "$g"
  any_exists "$g/pyproject.toml" "$g/setup.py" "$g"/requirements*.txt && python_group "$g"
  [[ -f "$g/go.mod" ]] && go_group "$g"
  [[ -f "$g/Cargo.toml" ]] && rust_group "$g"
  if is_flutter "$g"; then
    row mobile-ui Flutter "$(paths_of "$g")" "$(in_dir "$g")flutter run" "$(in_dir "$g")flutter analyze" "" ""
  fi
  [[ -f "$g/dbt_project.yml" ]] && hint data dbt "$(paths_of "$g")"
  [[ -d "$g/dags" ]] && hint data Airflow "$(prefix_of "$g")dags/**"
done <<<"$groups"

# Native app folders (an ios/ with an Xcode project or Podfile, an android/ with
# Gradle files) up to two levels down, unless they belong to a Flutter app.
while IFS= read -r d; do
  d="${d#./}"; [[ -n "$d" ]] || continue
  p="${d%/*}"; [[ "$p" == "$d" ]] && p=.
  is_flutter "$p" && continue
  case "${d##*/}" in
    ios)     any_exists "$d"/*.xcodeproj "$d"/*.xcworkspace "$d/Podfile" && hint mobile-ui iOS "$d/**" ;;
    android) any_exists "$d"/build.gradle* "$d"/settings.gradle* && hint mobile-ui Android "$d/**" ;;
  esac
done < <(find . -maxdepth 3 -type d \( -name node_modules -o -name .git -o -name vendor -o -name dist \
           -o -name build -o -name target -o -name .venv -o -name venv \) -prune \
         -o -type d \( -name ios -o -name android \) -print 2>/dev/null | tr -d '\r' | LC_ALL=C sort)

# Root-only hints: infrastructure as code, and a native app at the root.
s="" p=""
any_exists ./*.tf && { s=Terraform; p="*.tf"; }
[[ -d helm ]] && { s="${s:+$s, }Helm"; p="${p:+$p }helm/**"; }
[[ -d k8s ]] && { s="${s:+$s, }Kubernetes"; p="${p:+$p }k8s/**"; }
[[ -n "$s" ]] && hint infra "$s" "$p"
if ! is_flutter .; then
  any_exists ./*.xcodeproj ./*.xcworkspace && hint mobile-ui iOS "**"
  [[ -f app/src/main/AndroidManifest.xml ]] && hint mobile-ui Android "app/**"
fi

# --- the proposal ---

# Two groups proposing the same surface: the later ones get the folder's name,
# lowercased with anything outside [a-z0-9-] as one dash (web-ui, then
# web-ui-admin-portal for apps/Admin_Portal), since a surface names one row and
# kickoff takes only those characters. Two hints for the same surface become one
# row with both stacks and paths.
table=$( { printf '%s' "$ROWS"; printf '%s' "$HINTS"; } | awk -F'\t' -v OFS='\t' '
  $1 == "" { next }
  $1 ~ / \(check\)$/ {
    if ($1 in hi) {
      i = hi[$1]; split(r[i], c, "\t")
      if (index(", " c[2] ", ", ", " $2 ", ") == 0) c[2] = c[2] ", " $2
      if (index(" " c[3] " ", " " $3 " ") == 0) c[3] = c[3] " " $3
      r[i] = c[1] OFS c[2] OFS c[3] OFS OFS OFS OFS; next
    }
    r[++n] = $0; hi[$1] = n; next
  }
  {
    s = $1
    if (s in used) {
      p = $3; sub(/\/\*\*$/, "", p); sub(/.*\//, "", p)
      p = tolower(p); gsub(/[^a-z0-9-]+/, "-", p); gsub(/-+/, "-", p); gsub(/^-|-$/, "", p)
      s = (p == "") ? $1 : $1 "-" p   # nothing is left of the root, "**"
      while (s in used) s = s "-2"
    }
    used[s] = 1; $1 = s; r[++n] = $0
  }
  END {
    for (i = 1; i <= n; i++) {
      k = split(r[i], c, "\t"); out = "|"
      for (j = 1; j <= 7; j++) out = out (c[j] == "" ? " |" : " " c[j] " |")
      print out
    }
  }')

proposal() {
  [[ -f "$TEMPLATE" ]] || { echo "detect-project: the template $TEMPLATE is missing." >&2; return 1; }
  # The template, with the generated rows in place of its placeholder rows and
  # without its placeholder generic command.
  TABLE="$table" awk '
    { sub(/\r$/, "") }
    /^\| </ { if (!done && ENVIRON["TABLE"] != "") print ENVIRON["TABLE"]; done = 1; next }
    /^### </ { skip = 1; next }
    skip && /^```/ { if (++fence == 2) { skip = 0; fence = 0 } next }
    skip { next }
    /^$/ { blank++; next }
    { while (blank) { print ""; blank-- } print }' "$TEMPLATE"
}

target="docs/product/project.md"
if [[ -z "$write" ]]; then
  proposal
  exit
fi
if [[ -e "$target" ]]; then
  echo "detect-project: $target already exists; left unchanged."
  exit 0
fi
out=$(proposal) || exit 1
mkdir -p docs/product && printf '%s\n' "$out" > "$target" && echo "detect-project: wrote $target"
