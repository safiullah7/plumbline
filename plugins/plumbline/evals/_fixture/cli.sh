#!/usr/bin/env bash
# Shared eval fixture for v0.4b: relnotes, a Python command line tool that turns
# a git tag range into release notes, used by hand and in CI (surface cli).
# Module "relnotes" has a vision and a finished feature (01-generate-notes) whose
# criteria the tests are named after. Sourcing this file leaves one commit on main.
#   source "$(dirname "$0")/../_fixture/cli.sh"
set -e
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

git init -q -b main
git config user.name eval
git config user.email eval@example.com
git config core.autocrlf false
mkdir -p relnotes tests docs/product/relnotes

project_profile no none "| cli | Python | relnotes/** tests/** pyproject.toml | python -m relnotes --help | mypy relnotes | ruff check . | pytest |"

cat > docs/product/relnotes/vision.md <<'EOT'
# Relnotes vision

Owner: product engineer

## Who it's for
Maintainers who cut a release by hand, and CI jobs that cut one on every tag.

## Problem
Release notes are copied from commit messages by hand, so they are late and
miss changes.

## Product principles
- Every command works with no terminal: in CI, piped, or with `--json`.
- Output goes to stdout, diagnostics to stderr, and the exit code says what happened.
- Never ask a question when the answer can be a flag.

## Features
Each feature is named by the outcome it changes for a user. Folder:
docs/product/relnotes/.
| Feature | Goal | Outcome (measurable) | Why next | Status |
| --- | --- | --- | --- | --- |
| 01-generate-notes | Notes from a tag range in one command | A release's notes take under 10 seconds | Hand-copied notes miss changes | Done |
EOT

mkdir -p docs/product/relnotes/01-generate-notes
cat > docs/product/relnotes/01-generate-notes/acceptance-criteria.md <<'EOT'
# Feature 01 acceptance criteria

Owner: product engineer. Every criterion is observable in stdout, stderr or the
exit code. Tests are named after these IDs.

| ID | Use case | Given | When | Then | Priority |
| --- | --- | --- | --- | --- | --- |
| AC-01-001 | UC-01-01 | a repo with tags v1.0 and v1.1 | `relnotes generate --since v1.0` | stdout lists the commits between them, one `- <subject>` line each, and the exit code is 0 | P0 |
| AC-01-002 | UC-01-01 | the same repo | `relnotes generate --since v9.9` | stdout is empty, stderr says `unknown tag: v9.9`, the exit code is 2 | P0 |
| AC-01-003 | UC-01-01 | the same repo | `relnotes generate --since v1.0 --json` | stdout is one JSON object with `version` and `changes`, nothing else | P0 |
| AC-01-004 | UC-01-02 | stdin is not a terminal | `relnotes publish --yes` | it publishes with no prompt and exits 0 | P0 |
EOT

cat > pyproject.toml <<'EOT'
[project]
name = "relnotes"
version = "0.5.1"
description = "Release notes from a git tag range"
requires-python = ">=3.11"
dependencies = []

[project.scripts]
relnotes = "relnotes.cli:main"

[project.optional-dependencies]
dev = ["pytest>=8", "mypy>=1.10", "ruff>=0.5"]
EOT

cat > relnotes/__init__.py <<'EOT'
"""Release notes from a git tag range."""
EOT

cat > relnotes/__main__.py <<'EOT'
from .cli import main

raise SystemExit(main())
EOT

cat > relnotes/gitlog.py <<'EOT'
"""Read commit subjects between two refs."""
import subprocess


class UnknownTag(Exception):
    pass


def subjects(since: str, until: str = "HEAD") -> list[str]:
    known = subprocess.run(["git", "rev-parse", "--verify", "--quiet", since], capture_output=True)
    if known.returncode != 0:
        raise UnknownTag(since)
    out = subprocess.run(
        ["git", "log", "--format=%s", f"{since}..{until}"], capture_output=True, text=True, check=True
    )
    return [line for line in out.stdout.splitlines() if line]
EOT

cat > relnotes/cli.py <<'EOT'
"""relnotes generate --since TAG [--json]   |   relnotes publish [--yes]

Exit codes: 0 ok, 1 failure, 2 usage error or unknown tag.
"""
import argparse
import json
import sys

from . import gitlog


def generate(args: argparse.Namespace) -> int:
    try:
        changes = gitlog.subjects(args.since)
    except gitlog.UnknownTag:
        print(f"unknown tag: {args.since}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps({"version": args.since, "changes": changes}))
    else:
        for subject in changes:
            print(f"- {subject}")
    return 0


def publish(args: argparse.Namespace) -> int:
    if not args.yes:
        if not sys.stdin.isatty():
            print("refusing to publish without --yes when stdin is not a terminal", file=sys.stderr)
            return 2
        if input("Publish the notes? [y/N] ").strip().lower() != "y":
            return 1
    print("published")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="relnotes", description="Release notes from a git tag range.")
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("generate", help="print notes for the commits since a tag")
    gen.add_argument("--since", required=True, help="the tag to start from")
    gen.add_argument("--json", action="store_true", help="print one JSON object instead of a list")
    gen.set_defaults(run=generate)

    pub = sub.add_parser("publish", help="publish the notes")
    pub.add_argument("--yes", action="store_true", help="don't ask for confirmation")
    pub.set_defaults(run=publish)

    args = parser.parse_args(argv)
    return args.run(args)
EOT

cat > tests/test_cli.py <<'EOT'
"""Tests are named after the feature 01 acceptance criteria."""
import json

from relnotes import cli, gitlog


def test_AC_01_001_generate_lists_subjects(monkeypatch, capsys):
    monkeypatch.setattr(gitlog, "subjects", lambda since, until="HEAD": ["Fix login", "Add export"])
    assert cli.main(["generate", "--since", "v1.0"]) == 0
    assert capsys.readouterr().out == "- Fix login\n- Add export\n"


def test_AC_01_002_unknown_tag_exits_2(monkeypatch, capsys):
    def boom(since, until="HEAD"):
        raise gitlog.UnknownTag(since)

    monkeypatch.setattr(gitlog, "subjects", boom)
    assert cli.main(["generate", "--since", "v9.9"]) == 2
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "unknown tag: v9.9" in captured.err


def test_AC_01_003_json_is_one_object(monkeypatch, capsys):
    monkeypatch.setattr(gitlog, "subjects", lambda since, until="HEAD": ["Fix login"])
    assert cli.main(["generate", "--since", "v1.0", "--json"]) == 0
    assert json.loads(capsys.readouterr().out) == {"version": "v1.0", "changes": ["Fix login"]}


def test_AC_01_004_publish_yes_does_not_prompt(monkeypatch, capsys):
    monkeypatch.setattr("builtins.input", lambda *_: (_ for _ in ()).throw(AssertionError("prompted")))
    assert cli.main(["publish", "--yes"]) == 0
    assert capsys.readouterr().out == "published\n"
EOT

git add -A
git commit -qm "relnotes CLI with feature 01 done"
