# Runbook: Deploy rollback and bulk-data operations

**Owner:** Salesforce Admin / Architect. Standards: docs/CHANGE_MANAGEMENT.md.

## Part A: Deploy rollback

### Symptoms
A release breaks something (errors on save, automation misfiring, tests failing in prod validation).

### Checks
1. What changed: the release's PR(s) and their `## Rollback` sections; `git log <prev-tag>..<tag>`.
2. Is it config or code? A flow or approval process can often be **deactivated** faster than a redeploy.
3. Is data affected? If automation wrote bad values, plan a data fix (Part B) after the rollback.

### Safe fix (fastest first)
1. **Kill switch, no deploy:**
   - flows: Setup → Flows → deactivate
   - billing sync: `Integration_Config__mdt.Zuora_Billing.Is_Active__c` = false (sync logs "Skipped")
   - approvals: deactivate `EH_Quote_Discount_Approval` (the VR still blocks over-threshold acceptance)
2. **Revert and redeploy:** `git revert -m 1 <merge-sha>` → PR (with its own rollback note) → `sf project deploy start --target-org <org>`. Or redeploy the previous tag: `git checkout <prev-tag> && sf project deploy start --target-org <org>`.
3. **Destructive parts** (deleted fields/classes) don't come back from a redeploy alone: recreate them from the previous tag, then restore data from backup.
4. **Scheduled Apex:** a redeploy of classes used by `EH Billing Auto-Retry` works because `Deployment.settings` allows it. If you disable that setting, abort the jobs first (Setup → Scheduled Jobs), then re-run `BillingRetryScheduler.scheduleEvery15Minutes()`.

### Closure evidence
Errors stop; `sf apex run test --test-level RunLocalTests` green; the rollback PR merged with notes.

## Part B: Bulk data operation (Data Loader / `sf data`)

Rule: **back up → dry run → upsert → verify → (roll back from backup)**.

1. **Back up** the target records and fields first:
   `sf data export bulk --query "SELECT Id, Account_Key__c, Practice_Type__c FROM Account" --output-file backup/accounts-<date>.csv --target-org <org>`
2. **Use external IDs** (`Account_Key__c`, `Contact_Key__c`, `Lead_Key__c`, `Billing_Charge_Id__c`, `Subscription_Key__c`) and **upsert**, never blind insert. Re-running must create 0 new records.
3. **Dry run** on a scratch org or sandbox with the same file. Duplicate rules alert but don't block bulk loads, so check *EH Data Quality* afterwards.
4. **Run:** `sf data upsert bulk --sobject Account --file data/accounts.csv --external-id Account_Key__c --line-ending LF --target-org <org>` (or Data Loader with the same key).
5. **Verify:** record counts, a sample of values, and job results (`sf data bulk results --job-id <id>`).
6. **Roll back:** upsert the backup CSV on the same external ID (restores old values). For bad inserts, delete by the job's success file Ids.

Bulk loads don't create Duplicate Record Sets (the duplicate rule's Report action only fires on UI saves). Run the duplicate scan (`scripts/seed/seed-q2c-3-duplicates.apex` pattern) or a Duplicate Job after big loads.

### Closure evidence
Backup file stored, job Ids recorded, verification query results attached to the change ticket.
