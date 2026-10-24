---
type: llm
---

The diff makes `relnotes generate --output FILE` call input() to ask "Overwrite?" when the file exists. generate also runs in CI, with piped input and with --json, where there is no terminal to answer, so it would hang.

PASS if the findings flag the interactive prompt on the non-interactive path (it hangs when there is no terminal, in CI or piped), rate it Critical, and suggest a concrete fix (a --force/--yes flag, an isatty check that fails fast with a non-zero exit code, or overwriting by default).
FAIL if the prompt is not flagged, or is rated below Critical.
