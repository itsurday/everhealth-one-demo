@IsTest
private class BillingSyncService_Test {
    @TestSetup
    static void setup() {
        Account acct = TestDataFactory.account('Lakeside Dental (fictional)');
        TestDataFactory.quotes(acct, TestDataFactory.recurringProduct('ZSIM-PLATFORM'), 1);
    }

    private static Quote theQuote() {
        return [SELECT Id, AccountId, Billing_Sync_Status__c, Billing_Subscription__c, Last_Sync_Log__c FROM Quote LIMIT 1];
    }

    private static Integration_Log__c theLog() {
        return [SELECT Id, Status__c, Attempt_Count__c, Error_Category__c, Sanitized_Error__c, HTTP_Status__c,
                    Next_Retry_At__c, Related_Subscription__c, Related_Account__c, Payload_Hash__c, Retried_By__c
                FROM Integration_Log__c LIMIT 1];
    }

    @IsTest
    static void acceptedQuoteSyncsAndWritesBack() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        Quote q = theQuote();

        Test.startTest();
        TestDataFactory.accept(new List<Quote>{ q });
        Test.stopTest();

        Integration_Log__c log = theLog();
        Assert.areEqual('Succeeded', log.Status__c);
        Assert.areEqual(1, log.Attempt_Count__c);
        Assert.areEqual(201, log.HTTP_Status__c);
        Assert.areEqual(64, log.Payload_Hash__c.length());
        Assert.areEqual(q.AccountId, log.Related_Account__c);

        Billing_Subscription__c sub = [SELECT Id, Account__c, Status__c, MRR__c, Source_Quote__c, Subscription_Key__c, Term_End_Date__c FROM Billing_Subscription__c];
        Assert.areEqual(q.AccountId, sub.Account__c);
        Assert.areEqual('Active', sub.Status__c);
        Assert.areEqual(200.00, sub.MRR__c);
        Assert.areEqual(q.Id, sub.Source_Quote__c);
        Assert.isTrue(sub.Subscription_Key__c.startsWith('Zuora (Simulated):A-S'));
        Assert.areEqual(sub.Id, log.Related_Subscription__c);

        Quote after = theQuote();
        Assert.areEqual('Synced', after.Billing_Sync_Status__c);
        Assert.areEqual(sub.Id, after.Billing_Subscription__c);
        Assert.areEqual(log.Id, after.Last_Sync_Log__c);
        Assert.isNotNull([SELECT Billing_Account_Number__c FROM Account WHERE Id = :q.AccountId].Billing_Account_Number__c);
        Zuora_Subscription_Sim__c zuora = [SELECT MRR__c, Status__c FROM Zuora_Subscription_Sim__c WHERE Subscription_Number__c = :sub.Subscription_Key__c.substringAfter(':')];
        Assert.areEqual(200.00, zuora.MRR__c, 'stub persisted its simulated Zuora record');
    }

    @IsTest
    static void reacceptingDoesNotSyncTwice() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        Quote q = theQuote();
        Test.startTest();
        TestDataFactory.accept(new List<Quote>{ q });
        Test.stopTest();

        BillingSyncService.enqueue(new Set<Id>{ q.Id });
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c]);
        Assert.areEqual(1, [SELECT COUNT() FROM Billing_Subscription__c]);
    }

    @IsTest
    static void rateLimitIsRetryableWithBackoff() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('RateLimit', true);
        Test.startTest();
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Test.stopTest();

        Integration_Log__c log = theLog();
        Assert.areEqual(RetryPolicy.RETRYABLE, log.Status__c);
        Assert.areEqual('Rate Limit', log.Error_Category__c);
        Assert.areEqual(429, log.HTTP_Status__c);
        Assert.isTrue(log.Sanitized_Error__c.startsWith('Rate Limit: '));
        Assert.isNotNull(log.Next_Retry_At__c);
        Assert.areEqual('Failed', theQuote().Billing_Sync_Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Billing_Subscription__c]);
    }

    @IsTest
    static void validationFailureIsPermanent() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('Validation', true);
        Test.startTest();
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Test.stopTest();

        Integration_Log__c log = theLog();
        Assert.areEqual(RetryPolicy.PERMANENT, log.Status__c);
        Assert.areEqual('Validation', log.Error_Category__c);
        Assert.isNull(log.Next_Retry_At__c, 'no auto-retry for validation');
    }

    @IsTest
    static void lastAllowedAttemptExhausts() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('Timeout', true);
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Integration_Log__c log = theLog();
        log.Attempt_Count__c = 2;
        log.Status__c = 'Queued';
        update log;

        Test.startTest();
        BillingSyncService.process(new Set<Id>{ log.Id });
        Test.stopTest();

        Assert.areEqual(RetryPolicy.EXHAUSTED, theLog().Status__c);
        Assert.areEqual(3, theLog().Attempt_Count__c);
    }

    @IsTest
    static void inactiveConfigSkips() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', false);
        Test.startTest();
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Test.stopTest();
        Assert.areEqual('Skipped', theLog().Status__c);
        Assert.areEqual('Not Sent', theQuote().Billing_Sync_Status__c);
    }

    @IsTest
    static void operatorCanRetryAfterFixingTheCause() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('Validation', true);
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Integration_Log__c failed = theLog();
        failed.Status__c = RetryPolicy.PERMANENT;
        update failed;

        User operator = TestDataFactory.user('ehop', new List<String>{ 'EH_Integration_Operator' });
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        BillingSyncService.RetryRequest request = new BillingSyncService.RetryRequest();
        request.logId = failed.Id;
        List<BillingSyncService.RetryResult> results;
        Test.startTest();
        System.runAs(operator) {
            results = BillingSyncService.retryFromFlow(new List<BillingSyncService.RetryRequest>{ request });
        }
        Test.stopTest();

        Assert.areEqual('Retry queued.', results[0].message);
        Integration_Log__c log = theLog();
        Assert.areEqual('Succeeded', log.Status__c);
        Assert.areEqual(operator.Id, log.Retried_By__c);
    }

    @IsTest
    static void retryOfSucceededLogIsANoOp() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        Test.startTest();
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Test.stopTest();
        User operator = TestDataFactory.user('ehop2', new List<String>{ 'EH_Integration_Operator' });
        System.runAs(operator) {
            Assert.areEqual(0, BillingSyncService.retry(new List<Id>{ theLog().Id }));
        }
    }

    @IsTest
    static void nonOperatorCannotRetryOrSeeErrors() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('RateLimit', true);
        Test.startTest();
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Test.stopTest();
        Id logId = theLog().Id;

        User sales = TestDataFactory.user('ehsales', new List<String>{ 'EH_Sales_User' });
        System.runAs(sales) {
            Assert.isFalse(Schema.SObjectType.Integration_Log__c.isAccessible(), 'sales users have no log access');
            Assert.isFalse(Schema.SObjectType.Integration_Log__c.fields.Sanitized_Error__c.isAccessible());
            try {
                BillingSyncService.retry(new List<Id>{ logId });
                Assert.fail('retry must be blocked without EH_Retry_Integration');
            } catch (BillingSyncService.BillingSyncException e) {
                Assert.isTrue(e.getMessage().contains('EH_Retry_Integration'));
            }
        }
        Assert.areEqual(RetryPolicy.RETRYABLE, theLog().Status__c, 'log unchanged');
    }

    @IsTest
    static void bulkAcceptanceSyncsEveryQuoteInChunkedJobs() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        Account acct = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2.Billing_Charge_Id__c = 'ZSIM-PLATFORM' LIMIT 1];
        List<Quote> many = TestDataFactory.quotes(acct, pbe, 120);

        Test.startTest();
        TestDataFactory.accept(many);
        Assert.areEqual(3, Limits.getQueueableJobs(), '120 quotes / chunk of 50 = 3 jobs');
        Test.stopTest();

        Assert.areEqual(120, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Succeeded']);
        Assert.areEqual(120, [SELECT COUNT() FROM Billing_Subscription__c]);
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Billing_Account_Number__c != null]);
    }

    @IsTest
    static void deletedQuoteFailsPermanently() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Integration_Log__c log = theLog();
        log.Related_Quote__c = null;
        log.Status__c = 'Queued';
        update log;

        Test.startTest();
        BillingSyncService.process(new Set<Id>{ log.Id });
        Test.stopTest();
        Assert.areEqual(RetryPolicy.PERMANENT, theLog().Status__c);
        Assert.areEqual('Validation', theLog().Error_Category__c);
    }

    @IsTest
    static void schedulerRequeuesDueRetries() {
        BillingAdapterFactory.testConfig = TestDataFactory.config('RateLimit', true);
        TestDataFactory.accept(new List<Quote>{ theQuote() });
        Integration_Log__c log = theLog();
        log.Status__c = RetryPolicy.RETRYABLE;
        log.Attempt_Count__c = 1;
        log.Next_Retry_At__c = System.now().addMinutes(-1);
        update log;
        BillingAdapterFactory.testConfig = TestDataFactory.config('None', true);

        Test.startTest();
        new BillingRetryScheduler().execute(null);
        Test.stopTest();

        Assert.areEqual('Succeeded', theLog().Status__c);
        Assert.areEqual(2, theLog().Attempt_Count__c);
    }

    @IsTest
    static void schedulesFourJobs() {
        Test.startTest();
        BillingRetryScheduler.scheduleEvery15Minutes();
        Assert.areEqual(0, BillingRetryScheduler.scheduleEvery15Minutes(), 'second call is a no-op');
        Test.stopTest();
        Assert.areEqual(4, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :BillingRetryScheduler.JOB_NAME + '%']);
    }
}
