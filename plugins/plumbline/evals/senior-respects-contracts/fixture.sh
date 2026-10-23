#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/clinic.sh"
ready_plan
git add -A
git commit -qm "Dev plan approved"
