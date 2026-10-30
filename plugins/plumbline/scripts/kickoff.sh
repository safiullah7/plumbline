#!/usr/bin/env bash
# Creates a feature's docs folder from the kickoff templates and makes it the
# current feature. /plumbline:kickoff and /plumbline:build run it; it never
# creates a branch or commits (the skills do that).
#   kickoff.sh <module> <feature-slug> [--profile standard|full] [--ux|--no-ux]
#              [--new-module] [--surfaces s1,s2] [--security none|attacks|independent]
#   kickoff.sh <area> phase-NN
#   kickoff.sh --set-security none|attacks|independent
# Module form (defaults: full, UX): adds the module docs that are missing
# (vision, design-principles when UX, decisions, changes), then
# docs/product/<module>/<nn>-<slug>/ with the next repo-wide number (in a legacy
# area, one with a phases/ folder: phases/phase-<nn>/), the templates/standard/
# overlay for the standard profile, and .plumbline (with the slug, so a legacy
# area can refuse the same feature twice). The copied docs say "Feature <nn>"
# where the templates say "Phase <nn>". Without UX there's no ux.md. There's no
# prototypes/ folder: product writes the screens as text in ux.md.
# --surfaces names the feature's surfaces (a name is one of the ten kinds, or a
# kind plus "-<name>": web-ui-shop); an unknown name is a usage error. It's kept
# as given in .plumbline's surfaces=. Each kind with a templates/surface/ overlay
# (mobile-ui, api, ai, cli) applies it once, after the profile overlay: <doc>.append.md
# is appended to the feature's <doc>.md if that doc exists, any other file is
# copied, never over an existing one. Without --ux or --no-ux, --surfaces makes
# UX yes only when a surface is a web-ui, mobile-ui or desktop-ui; without
# --surfaces, UX stays yes.
# Legacy form, as v0.3's kickoff: the area docs that are missing, then
# docs/product/<area>/phases/phase-NN/ (the v0.3 file set, with prototypes/), no
# .plumbline. It takes any area name and phase id v0.3's hand kickoff took
# (Vet_Records phase-1, phase-03-auth); the module form needs lowercase slugs.
# Both write .claude/current-phase, print "added <path>" for each module or area
# doc they add, and print the feature folder (repo-relative) as the last line.
# --security <level> (module form only) writes security=<level> as the last line of
# .plumbline and, for attacks or independent, creates security.md from
# templates/security/. none, or no flag, writes neither.
# --set-security <level> (no other argument) raises the active feature's level
# (.claude/current-phase; module or legacy form): it replaces the security= line,
# creates security.md if it is missing (never over an existing one), and gives a
# legacy phase its first .plumbline. The same level changes nothing (it only adds a
# missing security.md); a lower level or an unknown one exits 1, and none writes
# nothing. It never exits 2.
# Exit 0 = created, 1 = usage or the feature already exists, 2 = --new-module on
# a module that already exists. On 1 and 2 nothing is changed.
source "$(dirname "${0//\\//}")/lib.sh"
usage() {
  [[ -n "${1:-}" ]] && echo "kickoff: $1" >&2
  echo "usage: kickoff.sh <module> <feature-slug> [--profile standard|full] [--ux|--no-ux] [--new-module] [--surfaces s1,s2] [--security none|attacks|independent]" >&2
  echo "       kickoff.sh <area> phase-NN" >&2
  echo "       kickoff.sh --set-security none|attacks|independent" >&2
  exit 1
}
exists() { echo "kickoff: $1 already exists; nothing changed." >&2; exit 1; }

NAME_RE='^[a-z0-9][a-z0-9-]*$'
TPL="$PLUMBLINE_SCRIPTS/../skills/kickoff/templates"
[[ -d "$TPL/phase" ]] || { echo "kickoff: templates not found at $TPL" >&2; exit 1; }
cd "$PROJECT_DIR" || exit 1

# security.md from its template into a feature folder: "Feature <nn>" in the title
# for a module-form feature, "Phase <nn>" for a legacy phase; never over a file.
make_security_md() { # feature folder, number, Feature|Phase
  local dst="$1/security.md"
  [[ -e "$dst" ]] && return 0
  [[ -f "$TPL/security/security.md" ]] || { echo "kickoff: $TPL/security/security.md not found" >&2; return 1; }
  sed -e "s/Phase <phase>/$3 $2/g" -e "s/<phase>/$2/g" "$TPL/security/security.md" > "$dst" && echo "added ${dst#"$PROJECT_DIR"/}"
}

# --set-security: raise the active feature's level (see the header).
set_security() { # level
  local want="$1" w c cur dir rel f tmp n word="Feature"
  w=$(security_rank "$want")
  (( w >= 0 )) || { echo "kickoff: '$want' isn't a security level (none, attacks or independent)" >&2; exit 1; }
  dir=$(phase_dir) || { echo "kickoff: no active feature (.claude/current-phase is missing)" >&2; exit 1; }
  dir="${dir%/}"
  [[ "$dir" != "$PROJECT_DIR" && -d "$dir" ]] || { echo "kickoff: .claude/current-phase doesn't point at a feature folder" >&2; exit 1; }
  rel="${dir#"$PROJECT_DIR"/}"; f="$dir/.plumbline"
  cur=$(feature_meta security | tr -d '[:space:]`'); c=$(security_rank "${cur:-none}")
  if (( w < c )); then
    echo "kickoff: security is $cur for $rel; a level can be raised, never lowered here (only the user waives a part, in security.md)" >&2
    exit 1
  fi
  if (( w == 0 )); then echo "kickoff: security stays none; nothing recorded."; exit 0; fi
  n=$(feature_meta number)
  if [[ -z "$n" ]]; then
    word=Phase; n="${rel##*/}"
    [[ "$n" =~ ^phase-([0-9]+) ]] && n="${BASH_REMATCH[1]}" || n=00
  fi
  if (( w > c )); then
    if [[ -f "$f" ]]; then
      tmp=$(mktemp)
      grep -vE '^[[:space:]]*security[[:space:]]*=' "$f" > "$tmp"
      [[ -s "$tmp" && -n "$(tail -c1 "$tmp")" ]] && echo >> "$tmp"
      echo "security=$want" >> "$tmp"
      cat "$tmp" > "$f"; rm -f "$tmp"
    else
      echo "security=$want" > "$f"
    fi
    echo "security=$want recorded in $rel/.plumbline"
  else
    echo "kickoff: security is already $want for $rel; nothing recorded."
  fi
  make_security_md "$dir" "$n" "$word" || exit 1
  exit 0
}

profile=full ux=yes ux_set="" new_module="" surfaces="" has_surfaces="" opts="" pos=()
sec_level="" has_security="" set_level="" has_set=""
while (( $# )); do
  case "$1" in
    --security)   (( $# >= 2 )) || usage; sec_level="$2"; has_security=1; opts=1; shift 2 ;;
    --security=*) sec_level="${1#*=}"; has_security=1; opts=1; shift ;;
    --set-security)   (( $# >= 2 )) || usage; set_level="$2"; has_set=1; shift 2 ;;
    --set-security=*) set_level="${1#*=}"; has_set=1; shift ;;
    --profile)    (( $# >= 2 )) || usage; profile="$2"; opts=1; shift 2 ;;
    --profile=*)  profile="${1#*=}"; opts=1; shift ;;
    --ux)         ux=yes; ux_set=1; opts=1; shift ;;
    --no-ux)      ux=no; ux_set=1; opts=1; shift ;;
    --new-module) new_module=1; opts=1; shift ;;
    --surfaces)   (( $# >= 2 )) || usage; surfaces="$2"; has_surfaces=1; opts=1; shift 2 ;;
    --surfaces=*) surfaces="${1#*=}"; has_surfaces=1; opts=1; shift ;;
    -*)           usage "unknown option $1" ;;
    *)            pos+=("$1"); shift ;;
  esac
done
if [[ -n "$has_set" ]]; then   # no positionals, so before the check below
  (( ${#pos[@]} == 0 )) && [[ -z "$opts" ]] || usage "--set-security takes no other argument"
  set_security "$set_level"
fi
(( ${#pos[@]} == 2 )) || usage
# The legacy form takes whatever v0.3's hand kickoff took (Vet_Records phase-01,
# phase-3, phase-03-auth) and refuses only names that would break a path or the
# sed substitutions below; the module form keeps the strict slug rule.
legacy=""; [[ "${pos[1]}" =~ ^phase-[0-9] ]] && legacy=1
if [[ -n "$legacy" ]]; then
  for n in "${pos[0]}" "${pos[1]}"; do
    case "$n" in
      .*|*[/\\\&[:space:][:cntrl:]]*) usage "'$n' can't be used as a folder name here (no slashes, spaces or &, and no leading dot)" ;;
    esac
  done
else
  [[ "${pos[0]}" =~ $NAME_RE ]] || usage "'${pos[0]}' isn't a valid name (lowercase letters, digits and dashes)"
  [[ "${pos[1]}" =~ $NAME_RE ]] || usage "'${pos[1]}' isn't a valid name (lowercase letters, digits and dashes)"
fi

# "room-schedules" -> "Room schedules", for <Module> and <Area>.
display() {
  local s="${1//-/ }"
  printf '%s%s\n' "$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"
}
fill() { # template, destination, sed expressions...
  local src="$1" dst="$2"; shift 2
  sed "$@" "$src" > "$dst"
}
gitkeep() { # folder, subfolders...
  local f="$1" d; shift
  for d in "$@"; do mkdir -p "$f/$d" && : > "$f/$d/.gitkeep"; done
}
current() { mkdir -p .claude && printf '%s\n' "$1" > .claude/current-phase; }

# --- Legacy form: kickoff.sh <area> phase-NN ---
if [[ -n "$legacy" ]]; then
  [[ -z "$opts" ]] || usage "the <area> phase-NN form takes no options"
  area="${pos[0]}"; [[ "${pos[1]}" =~ ^phase-([0-9]+) ]] && nn="${BASH_REMATCH[1]}"   # <phase> is the leading number
  feature="docs/product/$area/phases/${pos[1]}"
  [[ -e "$feature" ]] && exists "$feature"
  Area=$(display "$area")
  mkdir -p "$feature"
  for t in "$TPL"/area/*; do
    dst="docs/product/$area/${t##*/}"
    [[ -e "$dst" ]] && continue
    fill "$t" "$dst" -e "s/<Area>/$Area/g" -e "s/<area>/$area/g" && echo "added $dst"
  done
  for t in "$TPL"/phase/*; do fill "$t" "$feature/${t##*/}" -e "s/<phase>/$nn/g"; done
  gitkeep "$feature" contracts prototypes briefs
  current "$feature"
  printf '%s\n' "$feature"
  exit 0
fi

# --- Module form ---
module="${pos[0]}" slug="${pos[1]}" mdir="docs/product/${pos[0]}"
[[ "$profile" == standard || "$profile" == full ]] || usage "--profile is standard or full"
if [[ -n "$has_security" ]]; then
  (( $(security_rank "$sec_level") >= 0 )) || usage "--security is none, attacks or independent"
fi
if [[ -n "$has_surfaces" ]]; then
  [[ "$surfaces" =~ ^[a-z0-9][a-z0-9-]*(,[a-z0-9][a-z0-9-]*)*$ ]] \
    || usage "--surfaces is a comma-separated list, e.g. api,web-ui"
  has_ui="" overlays=""
  IFS=, read -r -a snames <<<"$surfaces"
  for s in "${snames[@]}"; do
    kind=$(surface_kind "$s") \
      || usage "'$s' isn't a surface (web-ui, mobile-ui, desktop-ui, api, service, cli, library, data, ai or infra, optionally followed by -<name>)"
    case "$kind" in
      web-ui|mobile-ui|desktop-ui) has_ui=1 ;;
    esac
    case "$kind" in
      mobile-ui) ov=mobile ;;
      api|ai|cli) ov="$kind" ;;
      *) continue ;;
    esac
    [[ " $overlays " == *" $ov "* ]] || overlays+="${overlays:+ }$ov"   # once per kind
  done
  if [[ -z "$ux_set" ]]; then if [[ -n "$has_ui" ]]; then ux=yes; else ux=no; fi; fi
fi
if [[ -n "$new_module" && -e "$mdir" ]]; then
  echo "kickoff: $mdir already exists, so it isn't a new module; nothing changed." >&2
  echo "Run again without --new-module to add the feature to it." >&2
  exit 2
fi
for d in "$mdir"/[0-9][0-9]*-*/; do   # the same slug under any number
  [[ -d "$d" ]] || continue
  d="${d%/}"
  [[ "${d##*/}" =~ ^[0-9]+-(.*)$ && "${BASH_REMATCH[1]}" == "$slug" ]] && exists "$d"
done
for f in "$mdir"/phases/*/.plumbline; do   # a legacy area keeps the slug in .plumbline
  [[ -f "$f" ]] || continue
  tr -d '\r' < "$f" | grep -qxF "slug=$slug" && exists "${f%/.plumbline}"
done
nn=$(next_feature_number)
if [[ -d "$mdir/phases" ]]; then feature="$mdir/phases/phase-$nn"; else feature="$mdir/$nn-$slug"; fi
[[ -e "$feature" ]] && exists "$feature"

Module=$(display "$module")
subst=(-e "s/Phase <phase>/Feature $nn/g" -e "s/<phase>/$nn/g" -e "s/<Module>/$Module/g" -e "s/<module>/$module/g")
mkdir -p "$feature"
docs="vision.md decisions.md changes.md"
[[ "$ux" == yes ]] && docs="vision.md design-principles.md decisions.md changes.md"
for name in $docs; do
  [[ -e "$mdir/$name" ]] && continue
  fill "$TPL/module/$name" "$mdir/$name" "${subst[@]}" && echo "added $mdir/$name"
done
tpls=("$TPL"/phase/*)
[[ "$profile" == standard ]] && tpls+=("$TPL"/standard/*)   # the overlay replaces same-named files
for t in "${tpls[@]}"; do
  name="${t##*/}"
  [[ "$ux" == no && "$name" == ux.md ]] && continue
  fill "$t" "$feature/$name" "${subst[@]}"
done
for ov in $overlays; do   # the surface overlays, after the profile overlay
  [[ -d "$TPL/surface/$ov" ]] || continue
  while IFS= read -r t; do
    rel="${t#"$TPL/surface/$ov/"}"
    if [[ "$rel" == *.append.md ]]; then
      doc="$feature/${rel%.append.md}.md"
      [[ -f "$doc" ]] || continue
      { echo; sed "${subst[@]}" "$t"; } >> "$doc"
    else
      [[ -e "$feature/$rel" ]] && continue
      [[ "$rel" == */* ]] && mkdir -p "$feature/${rel%/*}"
      fill "$t" "$feature/$rel" "${subst[@]}"
    fi
  done < <(find "$TPL/surface/$ov" -type f | LC_ALL=C sort)
done
gitkeep "$feature" contracts briefs
{
  echo "module=$module"
  echo "number=$nn"
  echo "profile=$profile"
  [[ -n "$has_surfaces" ]] && echo "surfaces=$surfaces"
  echo "ux=$ux"
  echo "created=$(date +%Y-%m-%d)"
  echo "slug=$slug"
  [[ -n "$has_security" && "$sec_level" != none ]] && echo "security=$sec_level"
} > "$feature/.plumbline"
case "$sec_level" in attacks|independent) make_security_md "$feature" "$nn" Feature >/dev/null ;; esac
current "$feature"
printf '%s\n' "$feature"
