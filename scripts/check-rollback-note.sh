#!/usr/bin/env bash
# Fails (exit 1) unless the PR body has a "## Rollback" section with real content.
# Usage: PR_BODY="..." scripts/check-rollback-note.sh     (or pipe the body on stdin)
set -euo pipefail

body="${PR_BODY-}"
if [ -z "$body" ] && [ ! -t 0 ]; then body="$(cat)"; fi
body="$(printf '%s\n' "$body" | tr -d '\r')"

if ! printf '%s\n' "$body" | grep -qE '^##[[:space:]]+Rollback'; then
  echo "::error::PR description has no '## Rollback' section. Say how to undo this change (see docs/CHANGE_MANAGEMENT.md)."
  exit 1
fi

# Text between "## Rollback" and the next "## " heading, minus HTML comments and blank lines.
section="$(printf '%s\n' "$body" | awk '
  /^##[[:space:]]+Rollback/ { on=1; next }
  on && /^##[[:space:]]/    { exit }
  on                        { print }
' | tr '\n' '\036' | sed 's/<!--[^>]*-->//g' | tr '\036' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true)"

normalized="$(printf '%s' "$section" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:].')"
case "$normalized" in
  ""|"n/a"|"na"|"none"|"tbd"|"todo"|"-")
    echo "::error::The '## Rollback' section is empty or a placeholder ('${section}'). Describe the rollback steps."
    exit 1 ;;
esac

echo "Rollback note found:"
printf '%s\n' "$section"
