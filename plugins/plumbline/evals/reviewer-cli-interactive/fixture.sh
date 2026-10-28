#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/cli.sh"
# The change: generate learns --output, and asks "Overwrite?" with input() when
# the file exists - on a path CI and --json callers use too.
cat > relnotes/cli.py <<'EOT'
"""relnotes generate --since TAG [--json] [--output FILE]   |   relnotes publish [--yes]

Exit codes: 0 ok, 1 failure, 2 usage error or unknown tag.
"""
import argparse
import json
import os
import sys

from . import gitlog


def generate(args: argparse.Namespace) -> int:
    try:
        changes = gitlog.subjects(args.since)
    except gitlog.UnknownTag:
        print(f"unknown tag: {args.since}", file=sys.stderr)
        return 2
    if args.output and os.path.exists(args.output):
        answer = input(f"{args.output} exists. Overwrite? [y/N] ")
        if answer.strip().lower() != "y":
            return 1
    if args.json:
        text = json.dumps({"version": args.since, "changes": changes}) + "\n"
    else:
        text = "".join(f"- {subject}\n" for subject in changes)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as out:
            out.write(text)
    else:
        sys.stdout.write(text)
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
    gen.add_argument("--output", help="write the notes to this file instead of stdout")
    gen.set_defaults(run=generate)

    pub = sub.add_parser("publish", help="publish the notes")
    pub.add_argument("--yes", action="store_true", help="don't ask for confirmation")
    pub.set_defaults(run=publish)

    args = parser.parse_args(argv)
    return args.run(args)
EOT
git diff > changes.diff
