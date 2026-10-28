#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/cli.sh"
# A repo that has never run Plumbline's build: no project profile yet.
git rm -q docs/product/project.md
git commit -qm "No project profile yet"
