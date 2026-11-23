#!/usr/bin/env bash
# Demo helper: POSTs the same simulated Zuora billing event twice to /billing/events.
# The first delivery is processed; the second comes back as "duplicate" (Duplicate_Count__c = 1).
# Usage: scripts/send-billing-event.sh [alias] [eventId]
set -euo pipefail
cd "$(dirname "$0")/.."
ALIAS="${1:-eh-demo}"
EVENT_ID="${2:-evt-demo-$(date +%s)}"

sub="$(sf data query --target-org "$ALIAS" --query "SELECT Name FROM Billing_Subscription__c ORDER BY CreatedDate LIMIT 1" --json \
  | sed -n 's/.*"Name": *"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$sub" ] || { echo "No Billing_Subscription__c in $ALIAS; run scripts/load-demo-data.sh first." >&2; exit 1; }

body=".billing-event.tmp.json" # relative path: works for sf on Windows and Unix
trap 'rm -f "$body"' EXIT
printf '{"eventId":"%s","eventType":"invoice.posted","occurredAt":"%s","subscription":{"subscriptionNumber":"%s"},"invoice":{"status":"Posted"}}\n' \
  "$EVENT_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sub" > "$body"
echo "Event $EVENT_ID for subscription $sub"
for delivery in 1 2; do
  echo "--- delivery $delivery"
  MSYS_NO_PATHCONV=1 sf api request rest /services/apexrest/billing/events --method POST --body "@$body" --target-org "$ALIAS"
  echo
done
