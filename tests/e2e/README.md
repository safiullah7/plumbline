# Mini-phase end-to-end benchmark

Runs one whole Plumbline phase on a tiny app with a real team: kickoff, spec, UI
text, dev plan, TDD build by two engineers, review, QA, signoff. It's the
quality and token benchmark between plugin versions. It takes about an hour and
uses a large share of a usage window, so run it before a release, not routinely.

1. Build the test repo:

       bash tests/e2e/setup.sh /d/Repos/plumbline-e2e

2. Open a new PowerShell window and start Claude Code there, pointing
   --plugin-dir at the plugin version to measure (a git worktree for an older
   version):

   ```powershell
   cd D:\Repos\plumbline-e2e; $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"; $env:CLAUDE_CODE_ENABLE_TODO_TOOLS="1"; $env:PLUMBLINE_HOOK_DEBUG="1"; claude --plugin-dir D:\Repos\plumbline\plugins\plumbline
   ```

3. Accept the trust prompt and paste:

       Read D:\Repos\plumbline\tests\e2e\prompt.md and do exactly what it says.

4. When e2e-report.md appears, record tokens per role:

       bash tests/tools/token-report.sh --latest 'D:\Repos\plumbline-e2e'

Compare quality (every AC tested and passing, no open questions, QA verdict, bugs)
and tokens per role with the previous version's run in `docs/evals/`.
