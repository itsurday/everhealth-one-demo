#!/usr/bin/env bash
# Self-test for check-rollback-note.sh. Run: bash scripts/check-rollback-note.test.sh
set -uo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0

expect() { # expect <0|1> <name> <body>
  PR_BODY="$3" bash "$dir/check-rollback-note.sh" >/dev/null 2>&1 </dev/null
  local got=$?
  if [ "$got" -eq "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $2 (expected $1, got $got)"; fi
}

expect 1 "no section"          $'## Summary\nAdds a field'
expect 1 "empty section"       $'## Summary\nx\n## Rollback\n\n## Testing\nok'
expect 1 "template comment"    $'## Rollback\n<!-- How do we undo this? -->\n'
expect 1 "placeholder N/A"     $'## Rollback\nN/A\n'
expect 1 "placeholder TBD"     $'## Rollback\n  tbd.  \n## Testing\nok'
expect 0 "real note"           $'## Summary\nx\n## Rollback\nRevert the commit and redeploy tag v1.2.0.\n## Testing\nok'
expect 0 "note after comment"  $'## Rollback\n<!-- How do we undo this? -->\nDeactivate flow EH_Renewal_Generator.'
expect 0 "last section, CRLF"  $'## Summary\r\nx\r\n## Rollback\r\nRestore data/backup/accounts.csv with upsert.\r\n'

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
