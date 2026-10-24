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
(node, pytest or go, plus `--dir <path>` for a package in a subfolder), `generic`
with its command below, or any other command, which gets the AC IDs as its last
argument. An empty AC tests cell fails the task gate until you write one of
those, or `none`. No cell may contain a `|`. Rows marked "(check)" are guesses
the gates ignore: keep them without the mark, or delete them.

With jest or vitest, an expected failure (`test.failing`, `test.fails`) that
fails as expected reports like any passing test, so it counts as the AC's
passing test; don't name one after an AC ID.

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
