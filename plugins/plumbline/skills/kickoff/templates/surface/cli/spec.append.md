## Command surface
| Command | Flags | Purpose |
| --- | --- | --- |

- Exit codes: 0 success; list each non-zero code and its meaning.
- stdout is for results, stderr is for messages and errors.
- Output formats: default text, plus any machine format (for example `--json`).
- `--help` for every command, with one example each.
- Non-interactive behaviour: never prompt when stdin is not a terminal; take
  every input from flags, files or environment variables.
