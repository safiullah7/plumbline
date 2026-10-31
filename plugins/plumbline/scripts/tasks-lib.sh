#!/usr/bin/env bash
# Shared task parsing for plan-tasks.sh and make-briefs.sh (source it after lib.sh).
# Reads a dev plan's "## Tasks" section: "### <owner>" headings (### lead for the
# lead's chores) and "- [AC-02-030 SEC-02-007] B4: Status changes (HIGH)" task
# lines, each followed by indented detail lines (Files:, Red (unit):, E2E:, Done
# when:, an optional "Blocked by: B1, L0", ...). CRLF plans work.
#
# tasks_parse <plan> prints one record per task, in plan order, fields joined by
# the unit separator (read them with IFS=$'\037'; a tab would collapse empty fields):
#   n  owner  label  ids  subject  rating  blocked-by  done-when  title  block
# n is the task's 1-based position in the whole plan; label is the explicit one
# (a "B4:" right after the brackets; 1-2 capitals then 1-3 digits) or T<n>; ids are
# the AC and SEC IDs on the task line, space-separated; subject is the task line
# without its "- " and its rating; title is the subject without the brackets and
# the label; blocked-by is comma-separated labels; block is the task line and its
# detail lines with the record separator (\036) for newlines (tr '\036' '\n').
# A duplicate label, a Blocked-by label no task has, a malformed Blocked-by entry
# or a task that blocks itself is reported on stderr and makes it return 1 with no records.
tasks_parse() { # plan
  awk -v US=$'\037' -v RS_=$'\036' '
    function fail(m) { print m > "/dev/stderr"; bad = 1 }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function flush(   s, lab, title, ids, rest, seen_id, k) {
      if (!open) return
      open = 0; n++
      s = line; sub(/^[-*][ \t]+/, "", s); s = trim(s)
      rating = ""
      if (match(s, /\((LOW|NORMAL|HIGH)\)[ \t]*$/)) {
        rating = substr(s, RSTART + 1); sub(/\).*$/, "", rating)
        s = trim(substr(s, 1, RSTART - 1))
      }
      title = s
      while (match(title, /^\[[^]]*\][ \t]*/)) title = substr(title, RLENGTH + 1)
      lab = ""
      if (match(title, /^[A-Z][A-Z]?[0-9][0-9]?[0-9]?:([ \t]|$)/)) {
        lab = title; sub(/:.*$/, "", lab)
        title = trim(substr(title, index(title, ":") + 1))
      }
      if (lab == "") lab = "T" n
      if (lab in at) fail("duplicate label " lab " (tasks " at[lab] " and " n ", \"" s "\"): give each task a unique label")
      else at[lab] = n
      ids = ""; rest = s
      while (match(rest, /(AC|SEC)-[0-9]+-[0-9]+/)) {
        seen_id = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        if (!(seen_id in idseen)) { idseen[seen_id] = 1; ids = ids (ids == "" ? "" : " ") seen_id }
      }
      for (k in idseen) delete idseen[k]
      rec[n] = n US owner US lab US ids US s US rating US blockedcsv US done US title US block
      block = ""; blockedcsv = ""; done = ""
    }
    { sub(/\r$/, "") }
    /^## / { flush(); intasks = ($0 ~ /^## Tasks/); owner = ""; next }
    !intasks { next }
    /^###[ \t]/ { flush(); owner = $0; sub(/^###[ \t]+/, "", owner); owner = trim(owner); next }
    /^[-*][ \t]/ {
      flush()
      if (owner == "") next
      open = 1; line = $0; block = $0; blockedcsv = ""; done = ""
      next
    }
    /^[ \t]+[^ \t]/ && open {
      block = block RS_ $0
      t = trim($0)
      if (tolower(t) ~ /^blocked by:/) {
        v = trim(substr(t, 12)); nb = split(v, parts, /[ \t,;]+/)
        for (i = 1; i <= nb; i++) {
          p = parts[i]; sub(/\.$/, "", p)
          if (p == "" || tolower(p) == "none" || p == "-") continue
          if (p !~ /^[A-Z][A-Z]?[0-9][0-9]?[0-9]?$/) { fail("task \"" trim(line) "\": Blocked by entry \"" p "\" is not a label (like B1 or T3)"); continue }
          blockedcsv = blockedcsv (blockedcsv == "" ? "" : ",") p
        }
      } else if (tolower(t) ~ /^done when:/) {
        done = trim(substr(t, 11)); gsub(/\t/, " ", done)
      }
      next
    }
    /^[ \t]*$/ { next }
    { flush() }   # prose between tasks ends the block
    END {
      flush()
      for (i = 1; i <= n; i++) {
        split(rec[i], f, US); nb = split(f[7], bl, ",")
        for (j = 1; j <= nb; j++) {
          if (bl[j] == "") continue
          if (bl[j] == f[3]) fail("task " f[3] " (\"" f[5] "\") is blocked by itself")
          else if (!(bl[j] in at)) fail("task " f[3] " (\"" f[5] "\"): Blocked by " bl[j] ", but no task has that label (labels are written like \"- [AC-01-001] B1: Title (NORMAL)\"; a task with none is T<its position in the plan>)")
        }
      }
      if (bad) exit 1
      for (i = 1; i <= n; i++) print rec[i]
    }' "$1"
}

# The task-created gate's rule (task-created-gate.sh): a subject names an AC or
# SEC ID, or starts with [chore].
task_subject_ok() { # subject
  local shopt_nc; shopt_nc=$(shopt -p nocasematch)
  [[ "$1" =~ (AC|SEC)-[0-9]+-[0-9]+ ]] && return 0
  shopt -s nocasematch
  local rc=1
  [[ "$1" =~ ^[[:space:]]*\[chore\] ]] && rc=0
  eval "$shopt_nc"
  return $rc
}
