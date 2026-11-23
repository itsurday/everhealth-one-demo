/**
 * Inbound billing events from Zuora (simulated): POST /services/apexrest/billing/events
 * Idempotent on External_Event_Key__c = "ZUORA_SIM:<eventId>": a repeated event is recorded as a duplicate, not re-applied.
 * Authenticated callers only (integration user with EH_Integration_API); no guest access.
 *
 * without sharing: integration endpoint that writes system records (logs, subscriptions) for any account;
 * access is gated by Apex class access in the EH_Integration_API permission set.
 */
@RestResource(urlMapping='/billing/events')
global without sharing class BillingEventsResource {
    private static final String SOURCE_KEY = 'ZUORA_SIM';
    private static final Set<String> EVENT_TYPES = new Set<String>{ 'subscription.created', 'subscription.updated', 'subscription.cancelled', 'invoice.posted' };
    private static final Set<String> SUBSCRIPTION_STATUSES = new Set<String>{ 'Draft', 'Pending Activation', 'Active', 'Suspended', 'Cancelled', 'Expired' };
    private static final Set<String> INVOICE_STATUSES = new Set<String>{ 'Draft', 'Posted', 'Cancelled', 'Error' };

    /** API response body. */
    public class Result {
        public Integer statusCode;
        public String status;
        public String correlationId;
        public String message;
    }

    public class EventPayload {
        public String eventId;
        public String eventType;
        public Datetime occurredAt;
        public SubscriptionPayload subscription;
        public InvoicePayload invoice;
    }

    public class SubscriptionPayload {
        public String subscriptionNumber;
        public String accountNumber;
        public String status;
        public Integer version;
        public Date termStartDate;
        public Date termEndDate;
        public Boolean autoRenew;
        public Decimal mrr;
    }

    public class InvoicePayload {
        public String status;
    }

    @HttpPost
    global static void receive() {
        Blob body = RestContext.request.requestBody;
        Result r = handle(body?.toString());
        RestContext.response.statusCode = r.statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(r, true));
    }

    /** Validates, de-duplicates, applies and logs one event. */
    public static Result handle(String body) {
        EventPayload evt;
        try {
            evt = (EventPayload) JSON.deserialize(body, EventPayload.class);
        } catch (Exception e) {
            return result(400, 'rejected', null, 'Body is not a valid billing event.');
        }
        String problem = validate(evt);
        if (problem != null) {
            return result(400, 'rejected', null, problem);
        }
        Integration_Log__c log = newInboundLog(evt, body);
        Database.SaveResult saved = Database.insert(log, false, AccessLevel.SYSTEM_MODE);
        if (!saved.isSuccess()) {
            return isDuplicateKey(saved) ? recordDuplicate(log.External_Event_Key__c) : result(500, 'error', null, 'Could not record the event.');
        }
        try {
            return apply(evt, log);
        } catch (Exception e) {
            finish(log, RetryPolicy.PERMANENT, 'Unknown', e.getMessage());
            return result(500, 'error', log.Correlation_Id__c, 'Processing failed; see the Integration Log.');
        }
    }

    private static String validate(EventPayload evt) {
        if (evt == null || String.isBlank(evt.eventId)) {
            return 'eventId is required.';
        }
        if (!EVENT_TYPES.contains(evt.eventType)) {
            return 'Unsupported eventType: ' + evt.eventType;
        }
        if (evt.subscription == null || String.isBlank(evt.subscription.subscriptionNumber)) {
            return 'subscription.subscriptionNumber is required.';
        }
        if (evt.subscription.status != null && !SUBSCRIPTION_STATUSES.contains(evt.subscription.status)) {
            return 'Unsupported subscription status: ' + evt.subscription.status;
        }
        if (evt.invoice?.status != null && !INVOICE_STATUSES.contains(evt.invoice.status)) {
            return 'Unsupported invoice status: ' + evt.invoice.status;
        }
        return null;
    }

    private static Result apply(EventPayload evt, Integration_Log__c log) {
        String key = BillingSyncService.SUBSCRIPTION_SOURCE + ':' + evt.subscription.subscriptionNumber;
        Billing_Subscription__c existing = BillingSubscriptionSelector.byKeys(new Set<String>{ key }).get(key);
        Datetime occurredAt = evt.occurredAt ?? System.now();
        if (existing != null && existing.External_Updated_At__c != null && occurredAt < existing.External_Updated_At__c) {
            log.Related_Subscription__c = existing.Id;
            finish(log, 'Skipped', null, 'Stale event: older than the last applied event.');
            return result(200, 'ignored', log.Correlation_Id__c, 'Older than the last applied event.');
        }
        Id accountId = existing?.Account__c;
        if (existing == null) {
            String acctNumber = evt.subscription.accountNumber ?? '';
            accountId = BillingSubscriptionSelector.accountIdsByBillingNumber(new Set<String>{ acctNumber }).get(acctNumber);
            if (accountId == null) {
                finish(log, RetryPolicy.PERMANENT, 'Validation', 'Unknown billing account ' + acctNumber);
                return result(422, 'rejected', log.Correlation_Id__c, 'Unknown billing account.');
            }
        }
        Billing_Subscription__c sub = toSubscription(evt, key, occurredAt, log.Id);
        if (existing == null) {
            sub.Account__c = accountId; // master-detail is not reparentable: set on insert only
        }
        Database.upsert(sub, Billing_Subscription__c.Subscription_Key__c, true, AccessLevel.SYSTEM_MODE);
        if (BillingAdapterFactory.config().Mode__c != 'NamedCredential') {
            StubBillingAdapter.mirror(sub); // keep the simulated Zuora store consistent with what billing told us
        }
        log.Related_Subscription__c = sub.Id;
        log.Related_Account__c = accountId;
        finish(log, BillingSyncService.SUCCEEDED, null, null);
        return result(200, 'processed', log.Correlation_Id__c, null);
    }

    private static Billing_Subscription__c toSubscription(EventPayload evt, String key, Datetime occurredAt, Id logId) {
        SubscriptionPayload s = evt.subscription;
        Billing_Subscription__c sub = new Billing_Subscription__c(
            Name = s.subscriptionNumber,
            Subscription_Key__c = key,
            Subscription_Number__c = s.subscriptionNumber,
            External_Updated_At__c = occurredAt,
            Last_Synced_At__c = System.now(),
            Last_Sync_Log__c = logId
        );
        // Only fields present in the event are written, so partial events don't blank existing values.
        String status = s.status ?? (evt.eventType == 'subscription.cancelled' ? 'Cancelled' : null);
        if (status != null) { sub.Status__c = status; }
        if (s.accountNumber != null) { sub.Billing_Account_Number__c = s.accountNumber; }
        if (s.version != null) { sub.Version__c = s.version; }
        if (s.termStartDate != null) { sub.Term_Start_Date__c = s.termStartDate; }
        if (s.termEndDate != null) { sub.Term_End_Date__c = s.termEndDate; }
        if (s.autoRenew != null) { sub.Auto_Renew__c = s.autoRenew; }
        if (s.mrr != null) { sub.MRR__c = s.mrr; }
        if (evt.invoice?.status != null) { sub.Last_Invoice_Status__c = evt.invoice.status; }
        return sub;
    }

    private static Integration_Log__c newInboundLog(EventPayload evt, String body) {
        return new Integration_Log__c(
            External_Event_Key__c = SOURCE_KEY + ':' + evt.eventId,
            External_Event_Id__c = evt.eventId,
            Event_Type__c = evt.eventType,
            Direction__c = 'Inbound',
            Source_System__c = BillingSyncService.SUBSCRIPTION_SOURCE,
            Target_System__c = 'Salesforce',
            Correlation_Id__c = IntegrationLogService.newCorrelationId(),
            Status__c = 'Processing',
            Attempt_Count__c = 1,
            Last_Attempt_At__c = System.now(),
            Payload_Hash__c = IntegrationLogService.hash(body)
        );
    }

    private static Boolean isDuplicateKey(Database.SaveResult saved) {
        for (Database.Error e : saved.getErrors()) {
            if (e.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    private static Result recordDuplicate(String key) {
        Integration_Log__c original = [
            SELECT Id, Correlation_Id__c, Duplicate_Count__c
            FROM Integration_Log__c
            WHERE External_Event_Key__c = :key
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        original.Duplicate_Count__c = (original.Duplicate_Count__c ?? 0) + 1;
        original.Last_Duplicate_At__c = System.now();
        Database.update(original, AccessLevel.SYSTEM_MODE);
        return result(200, 'duplicate', original.Correlation_Id__c, 'Already processed; duplicate recorded.');
    }

    private static void finish(Integration_Log__c log, String status, String category, String message) {
        log.Status__c = status;
        log.Completed_At__c = System.now();
        log.Error_Category__c = category;
        log.Sanitized_Error__c = message == null ? null : IntegrationLogService.sanitize(category ?? 'Info', message);
        Database.update(log, AccessLevel.SYSTEM_MODE);
    }

    private static Result result(Integer statusCode, String status, String correlationId, String message) {
        Result r = new Result();
        r.statusCode = statusCode;
        r.status = status;
        r.correlationId = correlationId;
        r.message = message;
        return r;
    }
}
