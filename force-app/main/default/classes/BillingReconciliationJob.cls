/**
 * SYNC-07: nightly reconciliation of Salesforce subscriptions against billing's own records (Zuora, simulated).
 * Catches silent drift that no sync error reports, e.g. a price changed directly in Zuora.
 * Each mismatch becomes one Integration_Log__c per subscription per day (Reconciliation_Status__c = Mismatch),
 * so it shows on the Q2C Sync Health dashboard and the operator queue. Resolving is a human decision.
 *
 * Schedulable -> enqueues the inner Runner (Queueable), because callouts aren't allowed from scheduled context
 * and a class can't be both Schedulable and Queueable.
 * without sharing: system job over every subscription, regardless of who owns the accounts.
 */
public without sharing class BillingReconciliationJob implements Schedulable {
    public static final String JOB_NAME = 'EH Billing Reconciliation';
    public static final String MISMATCH = 'Mismatch';
    /** Portfolio-scale bound; production would page through subscriptions in batches. */
    public static final Integer MAX_SUBSCRIPTIONS = 200;
    private static final String DAILY_05_00 = '0 0 5 * * ?';

    public void execute(SchedulableContext context) {
        System.enqueueJob(new Runner());
    }

    /** Callout-capable context for the comparison. */
    public without sharing class Runner implements Queueable, Database.AllowsCallouts {
        public void execute(QueueableContext context) {
            run();
        }
    }

    /** Compares and records mismatches. Returns the number of mismatched subscriptions. */
    public static Integer run() {
        BillingAdapter adapter = BillingAdapterFactory.create(BillingAdapterFactory.config());
        List<Billing_Subscription__c> subs = BillingSubscriptionSelector.forReconciliation(MAX_SUBSCRIPTIONS);
        Set<String> numbers = new Set<String>();
        for (Billing_Subscription__c s : subs) {
            numbers.add(s.Subscription_Number__c);
        }
        Map<String, BillingAdapter.Response> billing = adapter.getSubscriptions(numbers);

        List<Integration_Log__c> mismatches = new List<Integration_Log__c>();
        for (Billing_Subscription__c s : subs) {
            List<String> diffs = differences(s, billing.get(s.Subscription_Number__c));
            if (!diffs.isEmpty()) {
                mismatches.add(mismatchLog(s, diffs));
            }
        }
        Database.upsert(mismatches, Integration_Log__c.External_Event_Key__c, true, AccessLevel.SYSTEM_MODE);
        return mismatches.size();
    }

    @TestVisible
    private static List<String> differences(Billing_Subscription__c sf, BillingAdapter.Response zuora) {
        if (zuora == null) {
            return new List<String>{ 'not found in billing' };
        }
        List<String> diffs = new List<String>();
        if (sf.Status__c != zuora.status) {
            diffs.add('status Salesforce ' + sf.Status__c + ' vs billing ' + zuora.status);
        }
        if ((sf.MRR__c ?? 0).setScale(2) != (zuora.mrr ?? 0).setScale(2)) {
            diffs.add('MRR Salesforce ' + (sf.MRR__c ?? 0).setScale(2) + ' vs billing ' + (zuora.mrr ?? 0).setScale(2));
        }
        if (sf.Term_End_Date__c != zuora.termEndDate) {
            diffs.add('term end Salesforce ' + sf.Term_End_Date__c + ' vs billing ' + zuora.termEndDate);
        }
        return diffs;
    }

    private static Integration_Log__c mismatchLog(Billing_Subscription__c s, List<String> diffs) {
        return new Integration_Log__c(
            External_Event_Key__c = 'RECON:' + s.Subscription_Number__c + ':' + String.valueOf(Date.today()), // one per subscription per day
            Event_Type__c = 'subscription.reconcile',
            Direction__c = 'Inbound',
            Source_System__c = BillingSyncService.SUBSCRIPTION_SOURCE,
            Target_System__c = 'Salesforce',
            Correlation_Id__c = IntegrationLogService.newCorrelationId(),
            Related_Subscription__c = s.Id,
            Related_Account__c = s.Account__c,
            Status__c = RetryPolicy.PERMANENT,
            Error_Category__c = 'Validation',
            Reconciliation_Status__c = MISMATCH,
            Sanitized_Error__c = IntegrationLogService.sanitize('Mismatch', String.join(diffs, '; ')),
            Attempt_Count__c = 1,
            Last_Attempt_At__c = System.now(),
            Completed_At__c = System.now()
        );
    }

    /** Daily at 05:00 org time. Skips if already scheduled. Returns true if a job was created. */
    public static Boolean scheduleDaily() {
        if ([SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME WITH SYSTEM_MODE] > 0) {
            return false;
        }
        System.schedule(JOB_NAME, DAILY_05_00, new BillingReconciliationJob());
        return true;
    }
}
