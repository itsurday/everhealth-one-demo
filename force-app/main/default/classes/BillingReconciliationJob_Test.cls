@IsTest
private class BillingReconciliationJob_Test {
    private static final String NUM = 'A-S50000001';

    @TestSetup
    static void setup() {
        Account acct = TestDataFactory.account('Pinecrest Family Dental (fictional)');
        insert new Billing_Subscription__c(Name = NUM, Account__c = acct.Id, Subscription_Number__c = NUM,
            Subscription_Key__c = 'Zuora (Simulated):' + NUM, Status__c = 'Active', MRR__c = 766,
            Term_Start_Date__c = Date.today().addMonths(-2), Term_End_Date__c = Date.today().addMonths(10));
        // inserting an Active subscription fires the lifecycle flow only; the simulated Zuora row is created here
        insert new Zuora_Subscription_Sim__c(Name = NUM, Subscription_Number__c = NUM, Status__c = 'Active', MRR__c = 766,
            Term_End_Date__c = Date.today().addMonths(10));
    }

    private static List<Integration_Log__c> mismatchLogs() {
        return [SELECT Status__c, Reconciliation_Status__c, Sanitized_Error__c, Related_Subscription__c, Error_Category__c
                FROM Integration_Log__c WHERE Event_Type__c = 'subscription.reconcile'];
    }

    @IsTest
    static void matchingRecordsProduceNoLogs() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        Assert.areEqual(0, BillingReconciliationJob.run());
        Assert.areEqual(0, mismatchLogs().size());
    }

    @IsTest
    static void priceChangedInBillingIsFlaggedOncePerDay() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        Zuora_Subscription_Sim__c z = [SELECT Id FROM Zuora_Subscription_Sim__c LIMIT 1];
        z.MRR__c = 841; // e.g. an uplift applied directly in Zuora
        update z;

        Assert.areEqual(1, BillingReconciliationJob.run());
        Assert.areEqual(1, BillingReconciliationJob.run(), 'second run the same day');
        List<Integration_Log__c> logs = mismatchLogs();
        Assert.areEqual(1, logs.size(), 'one log per subscription per day');
        Assert.areEqual(BillingReconciliationJob.MISMATCH, logs[0].Reconciliation_Status__c);
        Assert.areEqual('Validation', logs[0].Error_Category__c);
        Assert.isTrue(logs[0].Sanitized_Error__c.contains('MRR Salesforce 766.00 vs billing 841.00'), logs[0].Sanitized_Error__c);
        Assert.areEqual([SELECT Id FROM Billing_Subscription__c LIMIT 1].Id, logs[0].Related_Subscription__c);
    }

    @IsTest
    static void statusTermAndMissingAreFlagged() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        Zuora_Subscription_Sim__c z = [SELECT Id FROM Zuora_Subscription_Sim__c LIMIT 1];
        z.Status__c = 'Cancelled';
        z.Term_End_Date__c = Date.today();
        update z;
        BillingReconciliationJob.run();
        String msg = mismatchLogs()[0].Sanitized_Error__c;
        Assert.isTrue(msg.contains('status Salesforce Active vs billing Cancelled'), msg);
        Assert.isTrue(msg.contains('term end'), msg);

        delete z;
        BillingReconciliationJob.run();
        Assert.isTrue(mismatchLogs()[0].Sanitized_Error__c.contains('not found in billing'));
    }

    @IsTest
    static void scheduledRunEnqueuesTheComparison() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        update new Zuora_Subscription_Sim__c(Id = [SELECT Id FROM Zuora_Subscription_Sim__c LIMIT 1].Id, MRR__c = 1);
        Test.startTest();
        new BillingReconciliationJob().execute((SchedulableContext) null);
        Test.stopTest();
        Assert.areEqual(1, mismatchLogs().size());
    }

    @IsTest
    static void scheduleDailyIsIdempotent() {
        Test.startTest();
        Boolean first = BillingReconciliationJob.scheduleDaily();
        Boolean second = BillingReconciliationJob.scheduleDaily();
        Test.stopTest();
        Assert.isTrue(first || [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :BillingReconciliationJob.JOB_NAME] == 1);
        Assert.isFalse(second);
    }
}
