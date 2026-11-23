/**
 * Owns the quote -> billing sync (STA §3.2, §3.4): enqueue on acceptance, process via the adapter,
 * write back IDs/status, categorize failures, and operator retry.
 *
 * without sharing: this is a system integration process that writes logs and subscriptions the
 * triggering user may not own or see. Operator retry is gated explicitly by the EH_Retry_Integration
 * custom permission, checked server-side.
 */
public without sharing class BillingSyncService {
    public static final String RETRY_PERMISSION = 'EH_Retry_Integration';
    public static final String SUBSCRIPTION_SOURCE = 'Zuora (Simulated)';
    public static final String QUEUED = 'Queued';
    public static final String SUCCEEDED = 'Succeeded';
    /** Logs per Queueable job; keeps an HTTP adapter under the 100-callout limit. */
    public static final Integer CHUNK_SIZE = 50;
    private static final Integer DEFAULT_MAX_ATTEMPTS = 3;
    private static final Integer DEFAULT_BACKOFF_SECONDS = 60;
    private static final Set<String> RETRY_ELIGIBLE = new Set<String>{ RetryPolicy.RETRYABLE, RetryPolicy.PERMANENT, RetryPolicy.EXHAUSTED };

    /** Raised for configuration and permission problems. */
    public class BillingSyncException extends Exception {}

    /** Creates one Queued log per newly accepted quote and starts the async sync. A quote is never synced twice. */
    public static void enqueue(Set<Id> quoteIds) {
        if (quoteIds.isEmpty()) {
            return;
        }
        Integration_Config__mdt cfg = BillingAdapterFactory.config();
        Map<String, Id> quoteByKey = new Map<String, Id>();
        for (Id quoteId : quoteIds) {
            quoteByKey.put(IntegrationLogService.quoteSyncKey(quoteId), quoteId);
        }
        for (Integration_Log__c existing : IntegrationLogSelector.byKeys(quoteByKey.keySet())) {
            quoteByKey.remove(existing.External_Event_Key__c); // already synced or awaiting retry
        }
        if (quoteByKey.isEmpty()) {
            return;
        }
        List<Integration_Log__c> logs = newOutboundLogs(quoteByKey, cfg.Is_Active__c);
        // allOrNone=false: a concurrent duplicate key means another transaction already queued that quote
        Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
        List<Integration_Log__c> created = new List<Integration_Log__c>();
        List<Quote> quotes = new List<Quote>();
        for (Integration_Log__c log : logs) {
            if (log.Id != null) {
                created.add(log);
                quotes.add(new Quote(Id = log.Related_Quote__c, Last_Sync_Log__c = log.Id,
                    Billing_Sync_Status__c = cfg.Is_Active__c ? QUEUED : 'Not Sent'));
            }
        }
        Database.update(quotes, AccessLevel.SYSTEM_MODE);
        if (cfg.Is_Active__c) {
            startJobs(new Map<Id, Integration_Log__c>(created).keySet());
        }
    }

    /** Operator retry. Requires EH_Retry_Integration. Returns how many logs were re-queued. */
    public static Integer retry(List<Id> logIds) {
        if (!FeatureManagement.checkPermission(RETRY_PERMISSION)) {
            throw new BillingSyncException('You need the ' + RETRY_PERMISSION + ' permission to retry billing syncs.');
        }
        List<Integration_Log__c> eligible = new List<Integration_Log__c>();
        for (Integration_Log__c log : IntegrationLogSelector.byIds(new Set<Id>(logIds))) {
            if (log.Direction__c == 'Outbound' && RETRY_ELIGIBLE.contains(log.Status__c)) {
                log.Status__c = QUEUED;
                log.Next_Retry_At__c = null;
                log.Retried_By__c = UserInfo.getUserId();
                eligible.add(log);
            }
        }
        if (eligible.isEmpty()) {
            return 0;
        }
        Database.update(eligible, AccessLevel.SYSTEM_MODE);
        startJobs(new Map<Id, Integration_Log__c>(eligible).keySet());
        return eligible.size();
    }

    /** Flow entry point for the EH_Integration_Retry screen flow. */
    @InvocableMethod(label='Retry billing sync' description='Operator retry of failed quote syncs. Requires EH_Retry_Integration.' category='EverHealth One')
    public static List<RetryResult> retryFromFlow(List<RetryRequest> requests) {
        List<Id> logIds = new List<Id>();
        for (RetryRequest r : requests) {
            logIds.add(r.logId);
        }
        String message = retry(logIds) == 0 ? 'Nothing to retry: the log is not in a failed state.' : 'Retry queued.';
        List<RetryResult> out = new List<RetryResult>();
        for (Integer i = 0; i < requests.size(); i++) {
            out.add(new RetryResult(message));
        }
        return out;
    }

    /** Flow input: the Integration_Log__c to retry. */
    public class RetryRequest {
        @InvocableVariable(label='Integration Log Id' required=true)
        public Id logId;
    }

    /** Flow output: message for the operator. */
    public class RetryResult {
        @InvocableVariable(label='Message')
        public String message;
        public RetryResult(String message) {
            this.message = message;
        }
    }

    /** Splits logs into CHUNK_SIZE jobs (no chaining needed). */
    public static void startJobs(Set<Id> logIds) {
        List<Id> chunk = new List<Id>();
        for (Id logId : logIds) {
            chunk.add(logId);
            if (chunk.size() == CHUNK_SIZE) {
                System.enqueueJob(new BillingSyncQueueable(new Set<Id>(chunk)));
                chunk.clear();
            }
        }
        if (!chunk.isEmpty()) {
            System.enqueueJob(new BillingSyncQueueable(new Set<Id>(chunk)));
        }
    }

    /** Runs in the Queueable: all callouts first, then all DML (no callouts after uncommitted work). */
    public static void process(Set<Id> logIds) {
        Integration_Config__mdt cfg = BillingAdapterFactory.config();
        BillingAdapter adapter = BillingAdapterFactory.create(cfg);
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        Set<Id> quoteIds = new Set<Id>();
        for (Integration_Log__c log : IntegrationLogSelector.byIds(logIds)) {
            if (log.Status__c == QUEUED) {
                logs.add(log);
                quoteIds.add(log.Related_Quote__c);
            }
        }
        Map<Id, Quote> quotes = QuoteSelector.byIdsWithLines(quoteIds);
        Map<Id, BillingAdapter.Response> responses = new Map<Id, BillingAdapter.Response>();
        for (Integration_Log__c log : logs) {
            responses.put(log.Id, call(adapter, log, quotes.get(log.Related_Quote__c)));
        }
        new ResultWriter(cfg, quotes).write(logs, responses);
        adapter.commitWork();
    }

    private static BillingAdapter.Response call(BillingAdapter adapter, Integration_Log__c log, Quote q) {
        if (q == null) {
            BillingAdapter.Response missing = new BillingAdapter.Response();
            missing.httpStatus = 400;
            missing.errorMessage = 'Quote no longer exists';
            return missing;
        }
        BillingAdapter.Request req = toRequest(log.External_Event_Key__c, q);
        Long started = System.currentTimeMillis();
        BillingAdapter.Response res = adapter.createSubscription(req);
        log.Duration_Ms__c = System.currentTimeMillis() - started;
        log.Payload_Hash__c = IntegrationLogService.hash(JSON.serialize(req));
        return res;
    }

    private static BillingAdapter.Request toRequest(String key, Quote q) {
        BillingAdapter.Request req = new BillingAdapter.Request();
        req.idempotencyKey = key;
        req.quoteId = q.Id;
        req.quoteNumber = q.QuoteNumber;
        req.quoteType = q.Quote_Type__c;
        req.accountId = q.AccountId;
        req.accountName = q.Account.Name;
        req.billingAccountNumber = q.Account.Billing_Account_Number__c;
        req.termMonths = q.Term_Months__c?.intValue();
        req.termStartDate = q.Term_Start_Date__c;
        for (QuoteLineItem li : q.QuoteLineItems) {
            BillingAdapter.Line line = new BillingAdapter.Line();
            line.chargeId = li.Product2.Billing_Charge_Id__c;
            line.productName = li.Product2.Name;
            line.chargeType = li.Product2.Charge_Type__c;
            line.billingPeriod = li.Product2.Billing_Period__c;
            line.quantity = li.Quantity;
            line.unitPrice = li.UnitPrice;
            line.discountPercent = li.Discount;
            req.lines.add(line);
        }
        return req;
    }

    private static List<Integration_Log__c> newOutboundLogs(Map<String, Id> quoteByKey, Boolean active) {
        Map<Id, Quote> quotes = QuoteSelector.accountIdsByQuote(new Set<Id>(quoteByKey.values()));
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (String key : quoteByKey.keySet()) {
            Id quoteId = quoteByKey.get(key);
            logs.add(new Integration_Log__c(
                External_Event_Key__c = key,
                Event_Type__c = 'quote.sync',
                Direction__c = 'Outbound',
                Source_System__c = 'Salesforce',
                Target_System__c = SUBSCRIPTION_SOURCE,
                Correlation_Id__c = IntegrationLogService.newCorrelationId(),
                Related_Quote__c = quoteId,
                Related_Account__c = quotes.get(quoteId)?.AccountId,
                Status__c = active ? QUEUED : 'Skipped',
                Attempt_Count__c = 0
            ));
        }
        return logs;
    }

    /** Applies adapter responses to logs, subscriptions, quotes and accounts with one DML per object. */
    private without sharing class ResultWriter { // same system context as the outer class
        private final Integration_Config__mdt cfg;
        private final Map<Id, Quote> quotes;
        private final Datetime now = System.now();
        private final Map<String, Billing_Subscription__c> subsByKey = new Map<String, Billing_Subscription__c>();
        private final Map<Id, String> subKeyByLog = new Map<Id, String>();
        private final Map<Id, Account> accounts = new Map<Id, Account>();

        ResultWriter(Integration_Config__mdt cfg, Map<Id, Quote> quotes) {
            this.cfg = cfg;
            this.quotes = quotes;
        }

        void write(List<Integration_Log__c> logs, Map<Id, BillingAdapter.Response> responses) {
            Set<String> successKeys = new Set<String>();
            for (BillingAdapter.Response res : responses.values()) {
                if (res.success) {
                    successKeys.add(SUBSCRIPTION_SOURCE + ':' + res.subscriptionNumber);
                }
            }
            Map<String, Billing_Subscription__c> existing = BillingSubscriptionSelector.byKeys(successKeys);
            for (Integration_Log__c log : logs) {
                BillingAdapter.Response res = responses.get(log.Id);
                log.Attempt_Count__c = (log.Attempt_Count__c ?? 0) + 1;
                log.Last_Attempt_At__c = now;
                log.HTTP_Status__c = res.httpStatus;
                if (res.success) {
                    applySuccess(log, res, existing);
                } else {
                    applyFailure(log, res);
                }
            }
            Database.upsert(subsByKey.values(), Billing_Subscription__c.Subscription_Key__c, true, AccessLevel.SYSTEM_MODE);
            Database.update(accounts.values(), AccessLevel.SYSTEM_MODE);
            Database.update(quoteUpdates(logs), AccessLevel.SYSTEM_MODE);
            Database.update(logs, AccessLevel.SYSTEM_MODE);
        }

        void applySuccess(Integration_Log__c log, BillingAdapter.Response res, Map<String, Billing_Subscription__c> existing) {
            Quote q = quotes.get(log.Related_Quote__c);
            String key = SUBSCRIPTION_SOURCE + ':' + res.subscriptionNumber;
            Billing_Subscription__c sub = new Billing_Subscription__c(
                Name = res.subscriptionNumber,
                Subscription_Key__c = key,
                Subscription_Number__c = res.subscriptionNumber,
                Billing_Account_Number__c = res.accountNumber,
                Version__c = res.version,
                Status__c = res.status,
                Term_Type__c = 'Termed',
                Term_Start_Date__c = res.termStartDate,
                Term_End_Date__c = res.termEndDate,
                MRR__c = res.mrr,
                Source_Quote__c = q.Id,
                Last_Synced_At__c = now,
                Last_Sync_Log__c = log.Id
            );
            if (!existing.containsKey(key)) {
                sub.Account__c = q.AccountId; // master-detail is not reparentable: set on insert only
            }
            subsByKey.put(key, sub);
            subKeyByLog.put(log.Id, key);
            if (String.isBlank(q.Account.Billing_Account_Number__c)) {
                accounts.put(q.AccountId, new Account(Id = q.AccountId, Billing_Account_Number__c = res.accountNumber));
            }
            log.Status__c = SUCCEEDED;
            log.Completed_At__c = now;
            log.Error_Category__c = null;
            log.Sanitized_Error__c = null;
            log.Next_Retry_At__c = null;
        }

        void applyFailure(Integration_Log__c log, BillingAdapter.Response res) {
            Integer maxAttempts = cfg.Max_Attempts__c?.intValue() ?? DEFAULT_MAX_ATTEMPTS;
            Integer backoff = cfg.Base_Backoff_Seconds__c?.intValue() ?? DEFAULT_BACKOFF_SECONDS;
            Integer attempts = log.Attempt_Count__c.intValue();
            String category = RetryPolicy.categorize(res.httpStatus);
            log.Error_Category__c = category;
            log.Sanitized_Error__c = IntegrationLogService.sanitize(category, res.errorMessage);
            log.Status__c = RetryPolicy.statusAfterFailure(category, attempts, maxAttempts);
            log.Next_Retry_At__c = log.Status__c == RetryPolicy.RETRYABLE ? RetryPolicy.nextAttemptAt(now, attempts, backoff) : null;
        }

        List<Quote> quoteUpdates(List<Integration_Log__c> logs) {
            List<Quote> out = new List<Quote>();
            for (Integration_Log__c log : logs) {
                if (log.Related_Quote__c == null || !quotes.containsKey(log.Related_Quote__c)) {
                    continue;
                }
                Quote q = new Quote(Id = log.Related_Quote__c, Last_Sync_Log__c = log.Id,
                    Billing_Sync_Status__c = log.Status__c == SUCCEEDED ? 'Synced' : 'Failed');
                if (subKeyByLog.containsKey(log.Id)) {
                    Id subId = subsByKey.get(subKeyByLog.get(log.Id)).Id;
                    q.Billing_Subscription__c = subId;
                    log.Related_Subscription__c = subId;
                }
                out.add(q);
            }
            return out;
        }
    }
}
