# Runbook: Duplicate billing event

**Applies to:** inbound events on `POST /services/apexrest/billing/events` (simulated Zuora).
**Owner:** Integration Operator. **Escalate to:** Architect.

## Symptoms
- Caller receives `200 {"status":"duplicate"}` with the original `correlationId`.
- The original Integration Log shows `Duplicate Count` > 0 and `Last Duplicate At`.

## Impact
None by design: the event was applied once. Duplicates are expected from webhook senders (retries, network blips).

## Checks
1. Find the log by `External Event Key` = `ZUORA_SIM:<eventId>`. Status should be **Succeeded** (or **Skipped** for a stale event).
2. Compare `Payload Hash` with the sender's payload if the content might differ under the same event ID.
3. Look for a burst: many duplicates in minutes usually means the sender didn't get our 200 (timeouts upstream).

## Safe fix
- Usual case: no action.
- Same event ID, **different** payload: the sender reused an ID. Don't edit the log; ask the sender for a new event ID and re-send.
- Burst: confirm the endpoint responds quickly (no long-running work in the request), and tell the sender's owner.

## Escalation
Duplicate count climbing on many events for > 30 minutes, or same ID with a different payload → Architect + billing system owner.

## Closure evidence
Subscription values match billing; one log per event ID; cause recorded.
