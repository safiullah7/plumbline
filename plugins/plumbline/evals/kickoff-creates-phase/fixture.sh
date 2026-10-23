#!/usr/bin/env bash
# An empty product repo with one commit on main.
set -e
git init -q -b main
git config user.name eval
git config user.email eval@example.com
git config core.autocrlf false
echo "# Clinic app" > README.md
git add -A
git commit -qm init
