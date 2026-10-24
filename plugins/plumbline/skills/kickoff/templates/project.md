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
The commands run from the repo root; an empty Typecheck, Lint or AC tests cell
skips that check. AC tests is an adapter (node, pytest or go, with
`--dir <path>` for a package in a subfolder), `generic` with its command below,
or any other command, which gets the AC IDs as its last argument. No cell may
contain a `|`. Rows marked "(check)" are guesses: keep them without the mark,
or delete them.

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
