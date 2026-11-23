#!/usr/bin/env bash
# Loads EverHealth One demo data into an org. Safe to re-run: CSVs upsert on external IDs,
# users are created only if missing, and the Apex seed steps check a marker first.
# Usage: scripts/load-demo-data.sh [alias]
set -euo pipefail
cd "$(dirname "$0")/.."
ALIAS="${1:-eh-demo}"

count() { # count <soql> -> number of rows
  sf data query --target-org "$ALIAS" --query "$1" --json | sed -n 's/.*"totalSize": *\([0-9]*\).*/\1/p' | head -1
}

echo "==> Demo users (Sam Sales = non-operator, Morgan Manager = approver)"
for def in sales-user sales-manager; do
  alias_name="$(sed -n 's/.*"Alias": *"\([^"]*\)".*/\1/p' "config/users/$def.json")"
  if [ "$(count "SELECT Id FROM User WHERE Alias = '$alias_name'")" = "0" ]; then
    sf org create user --target-org "$ALIAS" --definition-file "config/users/$def.json" >/dev/null
    echo "    created $alias_name"
  else
    echo "    $alias_name exists"
  fi
done

echo "==> Upserting CSVs on external IDs (Data Loader format)"
upsert() { # upsert <sobject> <file> <external id>
  sf data upsert bulk --target-org "$ALIAS" --sobject "$1" --file "data/$2" --external-id "$3" --line-ending LF --wait 10 >/dev/null
  echo "    $1 <- data/$2 (on $3)"
}
upsert Account accounts.csv Account_Key__c
upsert Contact contacts.csv Contact_Key__c
upsert Lead leads.csv Lead_Key__c
upsert Product2 products.csv Billing_Charge_Id__c

echo "==> Seed part 1: deals, quotes, acceptance (real sync path)"
sf apex run --target-org "$ALIAS" --file scripts/seed/seed-q2c-1.apex | grep -o 'DEBUG|SEED1:.*' | cut -d'|' -f2 || true

echo "==> Waiting for the billing sync jobs"
for _ in $(seq 1 24); do
  pending="$(count "SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'BillingSyncQueueable' AND Status IN ('Holding','Queued','Preparing','Processing')")"
  [ "$pending" = "0" ] && break
  sleep 5
done

echo "==> Seed part 2: amendments + inbound billing events"
sf apex run --target-org "$ALIAS" --file scripts/seed/seed-q2c-2.apex | grep -o 'DEBUG|SEED2:.*' | cut -d'|' -f2 || true

echo "==> Opportunity amounts (annualized from quotes)"
sf apex run --target-org "$ALIAS" --file scripts/seed/seed-q2c-amounts.apex | grep -o 'DEBUG|SEEDAMT:.*' | cut -d'|' -f2 || true

echo "==> Seed part 3: duplicate scan with the org's matching rules"
sf apex run --target-org "$ALIAS" --file scripts/seed/seed-q2c-3-duplicates.apex | grep -o 'DEBUG|SEED3:.*' | cut -d'|' -f2 || true

echo "==> Seed part 4: reconciliation (simulated Zuora store + one planted drift)"
sf apex run --target-org "$ALIAS" --file scripts/seed/seed-q2c-4-reconciliation.apex | grep -o 'DEBUG|SEED4:.*' | cut -d'|' -f2 || true

echo "==> Loaded: $(count "SELECT Id FROM Account WHERE Account_Key__c != null") accounts, $(count "SELECT Id FROM Billing_Subscription__c") subscriptions, $(count "SELECT Id FROM Integration_Log__c") integration logs"
