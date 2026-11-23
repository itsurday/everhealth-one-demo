#!/usr/bin/env bash
# Builds the EverHealth One demo org from source: scratch org -> deploy -> admin access -> auto-retry -> demo data.
# Usage: scripts/setup-org.sh [alias]        env: DEVHUB (default dev-hub), DAYS (default 30)
#        SKIP_CREATE=1 scripts/setup-org.sh eh-demo   # redeploy into an existing org
set -euo pipefail
cd "$(dirname "$0")/.."

ALIAS="${1:-eh-demo}"
DEVHUB="${DEVHUB:-dev-hub}"
DAYS="${DAYS:-30}"

if [ "${SKIP_CREATE:-0}" != "1" ]; then
  echo "==> Creating scratch org '$ALIAS' ($DAYS days) from Dev Hub '$DEVHUB'"
  sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" \
    --target-dev-hub "$DEVHUB" --duration-days "$DAYS" --wait 20
fi

echo "==> Deploying metadata"
sf project deploy start --target-org "$ALIAS" --wait 30

echo "==> Assigning permission set group EH_RevOps_Admin to the admin user"
username="$(sf org display --target-org "$ALIAS" --json | sed -n 's/.*"username": *"\([^"]*\)".*/\1/p' | head -1)"
user_id="$(sf data query --target-org "$ALIAS" --query "SELECT Id FROM User WHERE Username='$username'" --json | sed -n 's/.*"Id": *"\(005[^"]*\)".*/\1/p' | head -1)"
psg_id="$(sf data query --target-org "$ALIAS" --query "SELECT Id FROM PermissionSetGroup WHERE DeveloperName='EH_RevOps_Admin'" --json | sed -n 's/.*"Id": *"\(0PG[^"]*\)".*/\1/p' | head -1)"
if [ -z "$user_id" ] || [ -z "$psg_id" ]; then echo "Could not resolve admin user or PSG id" >&2; exit 1; fi
existing="$(sf data query --target-org "$ALIAS" --query "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId='$user_id' AND PermissionSetGroupId='$psg_id'" --json | grep -c '"Id"' || true)"
if [ "$existing" = "0" ]; then
  sf data create record --target-org "$ALIAS" --sobject PermissionSetAssignment --values "AssigneeId=$user_id PermissionSetGroupId=$psg_id"
else
  echo "    already assigned"
fi

echo "==> Scheduling auto-retry (every 15 min) and reconciliation (daily 05:00 org time); skips existing jobs"
apex_file="$(mktemp)"
printf "BillingRetryScheduler.scheduleEvery15Minutes();
BillingReconciliationJob.scheduleDaily();
" > "$apex_file"
sf apex run --target-org "$ALIAS" --file "$apex_file" >/dev/null
rm -f "$apex_file"

echo "==> Loading demo data"
bash scripts/load-demo-data.sh "$ALIAS"

cat <<EOF

==> Done. Open with: sf org open --target-org $ALIAS
Manual step (Quote Templates aren't deployable as metadata): see README "Quote template".
EOF

echo "Image URLs for the quote template header (Insert Image > Web Address):"
org_json="$(sf org display --target-org "$ALIAS" --json)"
org_id="$(printf '%s' "$org_json" | sed -n 's/.*"id": *"\(00D[^"]*\)".*/\1/p' | head -1)"
instance="$(printf '%s' "$org_json" | sed -n 's/.*"instanceUrl": *"\([^"]*\)".*/\1/p' | head -1)"
sf data query --target-org "$ALIAS" --query "SELECT Id, DeveloperName FROM Document WHERE Folder.DeveloperName = 'EH_Branding' ORDER BY DeveloperName DESC" --json \
  | sed -n 's/.*"Id": *"\(015[^"]*\)".*/\1/p' | while read -r doc_id; do
    echo "  $instance/servlet/servlet.ImageServer?id=$doc_id&oid=$org_id"
  done
echo "  (first = logo, second = divider)"
