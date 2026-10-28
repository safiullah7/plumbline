#!/usr/bin/env bash
# Generic AC test adapter, for stacks without a dedicated one (Rust, .NET,
# Gradle, Flutter, Swift, ...): runs the command the project wrote for a surface.
#   generic.sh --surface <s> [--dir <path>] "AC-01-001|AC-01-002"
# The command is the first fenced code block under "### <s>" in the
# "## Generic commands" section of docs/product/project.md. Before it runs:
#   {ids_regex}       -> AC[-_]01[-_]001|AC[-_]01[-_]002
#   {ids_underscored} -> AC_01_001 AC_01_002
# The block runs with bash -c in the repo root (or --dir, relative to it), so
# quote a placeholder that holds | or brackets: go test ./... -run '{ids_regex}'.
# Its output passes through unchanged.
# Exit = the command's exit code; 1 = no such block or folder; 2 = usage.
# Unlike the other adapters, a pass here doesn't prove each ID has a passing
# test, so a warning saying so always goes to stderr.
source "$(dirname "${0//\\//}")/../lib.sh"
NAME=generic
usage() { echo "usage: $NAME.sh --surface <s> [--dir <path>] \"<AC IDs>\"" >&2; exit 2; }
echo "generic: per-ID presence isn't proven; the command's exit code is the result." >&2

dir="" surface="" raw=""
while (( $# )); do
  case "$1" in
    --dir)       (( $# >= 2 )) || usage; dir="$2"; shift 2 ;;
    --dir=*)     dir="${1#*=}"; shift ;;
    --surface)   (( $# >= 2 )) || usage; surface="$2"; shift 2 ;;
    --surface=*) surface="${1#*=}"; shift ;;
    -*)          usage ;;
    *)           raw="$raw $1"; shift ;;
  esac
done
[[ -n "$surface" ]] || usage
# IDs split on |, commas or spaces; AC_01_001 and lowercase forms are accepted.
ids=""
set -f   # no globbing of the split tokens
for tok in $(printf '%s\n' "$raw" | tr -d '\r' | tr '|,' '  '); do
  [[ "$tok" =~ ^[Aa][Cc][-_]([0-9]+)[-_]([0-9]+)$ ]] || usage
  id="AC-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
  case " $ids " in *" $id "*) ;; *) ids="${ids:+$ids }$id" ;; esac
done
set +f
[[ -n "$ids" ]] || usage
ids_regex="" ids_underscored=""
for id in $ids; do
  IFS=- read -r _ a b <<<"$id"
  ids_regex="${ids_regex:+$ids_regex|}AC[-_]$a[-_]$b"
  ids_underscored="${ids_underscored:+$ids_underscored }AC_${a}_$b"
done

run_dir="$PROJECT_DIR"
if [[ -n "$dir" ]]; then
  case "$dir" in /*|[A-Za-z]:*) run_dir="$dir" ;; *) run_dir="$PROJECT_DIR/${dir#./}" ;; esac
fi
[[ -d "$run_dir" ]] || { echo "$NAME: no folder $run_dir" >&2; exit 1; }

doc="$PROJECT_DIR/docs/product/project.md"
[[ -f "$doc" ]] || { echo "$NAME: docs/product/project.md not found" >&2; exit 1; }

# The block: inside "## Generic commands" (up to the next "## " heading), the
# first ``` or ~~~ fence after "### <surface>" and before the next "###".
# Prints "ok" first when a block was found, so an empty block is told apart.
cmd=$(awk -v s="$surface" '
  function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
  { sub(/\r$/, "") }
  in_block {
    if (trim($0) ~ "^" fence) { done = 1; exit }
    print; next
  }
  /^## / { sect = (tolower(trim(substr($0, 4))) == "generic commands"); sub_ok = 0; next }
  !sect { next }
  /^### / { sub_ok = (trim(substr($0, 5)) == s); next }
  sub_ok && trim($0) ~ /^(```|~~~)/ {
    fence = substr(trim($0), 1, 3); in_block = 1; print "ok"; next
  }
  END { if (in_block && !done) exit 1 }
' "$doc") || { echo "$NAME: the \"### $surface\" block in docs/product/project.md has no closing fence" >&2; exit 1; }
if [[ "$cmd" != ok* ]]; then
  echo "$NAME: no \"### $surface\" command block under \"## Generic commands\" in docs/product/project.md" >&2
  exit 1
fi
cmd="${cmd#ok}"; cmd="${cmd#$'\n'}"
[[ -n "${cmd//[[:space:]]/}" ]] || { echo "$NAME: the \"### $surface\" command block is empty" >&2; exit 1; }

# Literal replacement (no pattern characters, unlike ${var//pat/rep}).
subst() { # text, placeholder, value
  local s="$1" out=""
  while [[ "$s" == *"$2"* ]]; do out="$out${s%%"$2"*}$3"; s="${s#*"$2"}"; done
  printf '%s' "$out$s"
}
cmd=$(subst "$cmd" '{ids_regex}' "$ids_regex")
cmd=$(subst "$cmd" '{ids_underscored}' "$ids_underscored")

cd "$run_dir" || exit 1
bash -c "$cmd"
