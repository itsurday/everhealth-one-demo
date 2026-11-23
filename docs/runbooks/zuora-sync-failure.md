# Runbook: Zuora sync failure (simulated Zuora)

**Applies to:** outbound quote → billing sync (`Integration_Log__c`, Direction = Outbound, Event Type = `quote.sync`).
**Owner:** Integration Operator (`EH_Integration_Operator`). **Escalate to:** Salesforce Architect, Billing.

## Symptoms
- Quote `Billing Sync Status` = **Failed**; no subscription number on the quote.
- Integration Log status **Retryable Failure** or **Permanent Failure**; list view *Failed Syncs (operator queue)*; dashboard *EH Q2C Sync Health*.

## Impact
Customer accepted a quote but billing has no subscription yet: no invoice, renewal clock not started, Account stays **Prospect**.

## Checks
1. Open the log: `Error Category`, `HTTP Status`, `Attempt Count`, `Next Retry At`, `Sanitized Error`.
2. Is it config? Setup → Custom Metadata Types → **Integration Config** → `Zuora_Billing`:
   - `Is Active` = true, `Mode` = Stub (demo) or NamedCredential, `Fail Mode` = **None** (anything else forces failures).
3. Is it data? For **Validation**: quote has Term Months + Term Start Date; every product has a `Billing Charge Id`.
4. Is it auth (NamedCredential mode)? Setup → Named Credentials → `Zuora_Billing` principal set.

## Safe fix
| Category | Action |
|---|---|
| Timeout / Network / Rate Limit / Server | Nothing: auto-retry runs every 15 min with backoff (`EH Billing Auto-Retry` jobs). Retry by hand only if urgent. |
| Validation | Fix the data, then **Retry Sync** on the log. |
| Authentication | Fix the credential, then **Retry Sync**. |

Retry is safe: it reuses the same idempotency key (`SF:QUOTE_SYNC:<QuoteId>`), so billing can't create a second subscription. Exhausted logs: see [exhausted-retry.md](exhausted-retry.md).

## Escalation
- Same category on > 5 logs in 1 hour, or any Authentication failure → Architect.
- Data fix needs a catalog change (new charge) → Billing + Salesforce Admin (change ticket, see docs/CHANGE_MANAGEMENT.md).

## Closure evidence
Log **Succeeded**, quote **Synced** with a subscription linked, Account **Customer**. Note the cause and fix on the ticket.
