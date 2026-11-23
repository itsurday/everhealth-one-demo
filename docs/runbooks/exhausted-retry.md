# Runbook: Exhausted retry

**Applies to:** outbound sync logs with status **Exhausted** (transient error hit `Max Attempts` in `Integration_Config__mdt`).
**Owner:** Integration Operator. **Escalate to:** Architect.

## Symptoms
- Log status **Exhausted**, `Attempt Count` = Max Attempts (default 3), category Timeout / Network / Rate Limit / Server.
- Quote `Billing Sync Status` = **Failed**. Auto-retry has stopped for this log.

## Impact
Same as a sync failure (no subscription in billing), and nothing will fix it automatically.

## Checks
1. Is the billing side healthy now? Check recent logs: are new syncs **Succeeded**?
2. Rate Limit: how many syncs ran in the last hour (dashboard *EH Q2C Sync Health*)? A bulk acceptance can exceed the vendor's limit.
3. Config: `Fail Mode` = None; `Max Attempts` / `Base Backoff Seconds` sensible.

## Safe fix
1. When billing is healthy: open the log → **Retry Sync** → confirm. One more attempt runs immediately with the same idempotency key.
2. If it fails again with the same transient category, stop. Don't loop manual retries; escalate.
3. Many exhausted logs after an outage: retry in small batches (≤ 50) to avoid re-triggering rate limits.

Only users with `EH_Retry_Integration` (in `EH_Integration_Operator`) can retry. The permission is checked on the server, so the button alone grants nothing.

## Escalation
Second failure after manual retry, or > 10 exhausted logs → Architect + billing system owner.

## Closure evidence
Log **Succeeded** with `Retried By` = you; quote **Synced**; incident note with the outage window.
