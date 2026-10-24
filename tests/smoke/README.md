# Live smoke test

Checks the hooks with a real agent team, then a Standard kickoff, the waiver lock and a
Quick change through `/plumbline:build`. Agent teams only run in an interactive
session, and the plugin and hooks are set when a session starts, so you run this
yourself. It takes about 20 minutes. The Quick part pushes to a local folder remote, so it ends
with a pushed branch, not a PR.

1. Push the branch you want to test, so Part 1 can confirm it matches GitHub.
2. Open a new PowerShell window and run (it deletes the old scratch folder first):

   ```powershell
   Remove-Item -Recurse -Force D:\Repos\plumbline-smoke -ErrorAction SilentlyContinue; mkdir D:\Repos\plumbline-smoke | Out-Null; cd D:\Repos\plumbline-smoke; $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"; $env:CLAUDE_CODE_ENABLE_TODO_TOOLS="1"; $env:PLUMBLINE_HOOK_DEBUG="1"; claude --plugin-dir D:\Repos\plumbline\plugins\plumbline
   ```

3. Accept the trust prompt, then paste:

   ```
   Read D:\Repos\plumbline\tests\smoke\prompt.md and do exactly what it says.
   ```

4. When it finishes, every row of its report table should say PASS.

Requires jq on PATH (`jq --version` in the same PowerShell window). If it was
just installed, open a fresh terminal first.
