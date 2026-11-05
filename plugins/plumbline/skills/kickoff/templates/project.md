# Project profile

Confirmed by: <user> on <date>. Edit it when the product changes shape.
Confirm: auto
Multi-tenant: no
Sensitive data: none

## Surfaces
| Surface | Stack | Paths | Run | Typecheck | Lint | AC tests |
| --- | --- | --- | --- | --- | --- | --- |
| <surface> | <stack> | <path globs> | <run command> (<url>) | <typecheck command> | <lint command> | <adapter> --dir <path> |
| <surface> | <stack> | <path globs> | <run command> | <typecheck command> | <lint command> | generic |

One row per surface: web-ui, mobile-ui, desktop-ui, api, service, cli, library,
data, ai or infra. Paths are space-separated globs, relative to the repo root.
The commands run in bash from the repo root, so write paths with forward
slashes (apps/web, not apps\web). An empty Typecheck or Lint cell skips that
check; `none` skips any check. AC tests is an adapter, written as just its name
(node, pytest, go or playwright, plus `--dir <path>` for a package in a subfolder), `generic`
with its command below, or any other command, which gets the AC IDs as its last
argument. Join two parts with `+` to run both (`node --dir storefront + playwright --dir storefront` runs unit and e2e tests); each part is an adapter. An empty AC tests cell fails the task gate until you write one of
those, or `none`. No cell may contain a `|`. Rows marked "(check)" are guesses
the gates ignore: keep them without the mark, or delete them.

An expected failure (Playwright `test.fail`, Vitest `test.fails`, Jest
`test.failing`, node:test `todo`, pytest `xfail`, Go `t.Skip("xfail: ...")`)
that names a finding in its reason or title (`finding #8 deferred`) reports
as `xfail`, never as a pass. Only an own attack under a deferred or accepted
security finding may be one; anywhere else an `xfail` fails the check. One
that names no finding counts as skipped. Don't name an expected failure after
an AC ID.

`Confirm:` is `auto` (decide, and ask only when unclear) or `always` (confirm
every triage). `Multi-tenant:` and `Sensitive data:` are read by the reviewer
and product agents.

## Generic commands
One `### <surface>` heading per surface whose AC tests cell is `generic`, then
one fenced block with the command. It runs from the repo root; `{ids_regex}`
and `{ids_underscored}` are replaced with the task's AC IDs, as a regex or in
the AC_01_001 form. A generic command proves only its exit code, not that each
AC has a test.

### <surface>
```
<command with {ids_regex} or {ids_underscored}>
```
