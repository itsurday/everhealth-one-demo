# Runbook: Reconciliation mismatch

**Applies to:** Integration Logs with Event Type `subscription.reconcile` and `Reconciliation Status` = **Mismatch**, written by the daily `EH Billing Reconciliation` job (05:00 org time).
**Owner:** Integration Operator with Billing. **Escalate to:** Architect, Billing lead.

## Symptoms
- *EH Q2C Sync Health* shows a Validation failure, or *Failed Syncs* lists a log like `Mismatch: MRR Salesforce 766.00 vs billing 841.00`.
- No sync error happened: the data drifted silently.

## Impact
Salesforce reports (renewals, MRR, pipeline) disagree with what billing invoices. Renewal quotes built from Salesforce would be priced wrong.

## Checks
1. Read the mismatch: which fields (status, MRR, term end) and both values.
2. **Which side is right?** Billing (Zuora) is the system of record for subscriptions (ADR-001).
   - A change made directly in Zuora (price uplift, manual cancel) → billing is right.
   - An admin edit or bad data load in Salesforce → billing is still right; find who changed it (field history on Billing Subscription).
   - A billing event that never arrived → check for a missing inbound log around that time.
3. In this simulation, billing's record is the **Zuora Subscription (Simulated)** tab.

## Safe fix
- Bring Salesforce in line with billing: ask Billing to re-send the subscription event (preferred: it goes through the normal idempotent intake and writes an audit log), or correct the Billing Subscription record with a note.
- If Salesforce was right (billing made a mistake): Billing fixes Zuora; don't edit Salesforce.
- Set the log's `Reconciliation Status` to **Resolved** and note what you did. Tomorrow's run confirms (no new mismatch log).

Don't use Retry Sync here: it's for outbound quote syncs. Reconciliation logs are inbound and are ignored by retry.

## Escalation
More than 3 mismatches in one run, or any mismatch on status (Active vs Cancelled), → Billing lead + Architect: possible missed events or a process gap.

## Closure evidence
Next daily run shows no mismatch for that subscription; log marked Resolved with the cause.
