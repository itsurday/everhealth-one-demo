@IsTest
private class BillingEventsResource_Test {
    private static final String SUB_NUMBER = 'A-S00000042';

    @TestSetup
    static void setup() {
        Account acct = TestDataFactory.account('Riverbend Chiropractic (fictional)');
        acct.Billing_Account_Number__c = 'A00000042';
        update acct;
    }

    private static String event(String eventId, String eventType, String status, String occurredAt) {
        return JSON.serialize(new Map<String, Object>{
            'eventId' => eventId,
            'eventType' => eventType,
            'occurredAt' => occurredAt,
            'subscription' => new Map<String, Object>{
                'subscriptionNumber' => SUB_NUMBER,
                'accountNumber' => 'A00000042',
                'status' => status,
                'version' => 1,
                'termStartDate' => '2026-01-01',
                'termEndDate' => '2026-12-31',
                'autoRenew' => true,
                'mrr' => 450
            }
        });
    }

    @IsTest
    static void createdEventCreatesSubscription() {
        BillingEventsResource.Result r = BillingEventsResource.handle(event('evt-1', 'subscription.created', 'Active', '2026-11-22T10:00:00Z'));
        Assert.areEqual(200, r.statusCode, 'message: ' + r.message);
        Assert.areEqual('processed', r.status);
        Assert.isNotNull(r.correlationId);

        Billing_Subscription__c sub = [SELECT Account__c, Status__c, MRR__c, Term_End_Date__c, Auto_Renew__c FROM Billing_Subscription__c];
        Assert.areEqual([SELECT Id FROM Account LIMIT 1].Id, sub.Account__c);
        Assert.areEqual('Active', sub.Status__c);
        Assert.areEqual(450, sub.MRR__c);
        Integration_Log__c log = [SELECT Status__c, Direction__c, External_Event_Key__c, Related_Subscription__c FROM Integration_Log__c];
        Assert.areEqual('Succeeded', log.Status__c);
        Assert.areEqual('Inbound', log.Direction__c);
        Assert.areEqual('ZUORA_SIM:evt-1', log.External_Event_Key__c);
        Assert.areEqual(450, [SELECT MRR__c FROM Zuora_Subscription_Sim__c WHERE Subscription_Number__c = :SUB_NUMBER].MRR__c, 'event mirrored into simulated Zuora');
    }

    @IsTest
    static void sameEventTwiceIsProcessedOnce() {
        String body = event('evt-dup', 'subscription.created', 'Active', '2026-11-22T10:00:00Z');
        BillingEventsResource.Result first = BillingEventsResource.handle(body);
        BillingEventsResource.Result second = BillingEventsResource.handle(body);

        Assert.areEqual('processed', first.status);
        Assert.areEqual(200, second.statusCode);
        Assert.areEqual('duplicate', second.status);
        Assert.areEqual(first.correlationId, second.correlationId, 'duplicate returns the original correlation id');
        Assert.areEqual(1, [SELECT COUNT() FROM Billing_Subscription__c]);
        Integration_Log__c log = [SELECT Duplicate_Count__c, Last_Duplicate_At__c FROM Integration_Log__c];
        Assert.areEqual(1, log.Duplicate_Count__c);
        Assert.isNotNull(log.Last_Duplicate_At__c);
    }

    @IsTest
    static void updateAndInvoiceEventsChangeStatus() {
        BillingEventsResource.handle(event('evt-a', 'subscription.created', 'Active', '2026-11-22T10:00:00Z'));
        BillingEventsResource.Result r = BillingEventsResource.handle(event('evt-b', 'subscription.cancelled', null, '2026-11-22T11:00:00Z'));
        Assert.areEqual('processed', r.status, 'message: ' + r.message);
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Billing_Subscription__c].Status__c, 'cancelled event without status implies Cancelled');

        Map<String, Object> inv = (Map<String, Object>) JSON.deserializeUntyped(event('evt-c', 'invoice.posted', null, '2026-11-22T12:00:00Z'));
        inv.put('invoice', new Map<String, Object>{ 'status' => 'Posted' });
        Assert.areEqual('processed', BillingEventsResource.handle(JSON.serialize(inv)).status);
        Assert.areEqual('Posted', [SELECT Last_Invoice_Status__c FROM Billing_Subscription__c].Last_Invoice_Status__c);
    }

    @IsTest
    static void staleEventIsIgnored() {
        BillingEventsResource.handle(event('evt-new', 'subscription.created', 'Active', '2026-11-22T12:00:00Z'));
        BillingEventsResource.Result r = BillingEventsResource.handle(event('evt-old', 'subscription.updated', 'Suspended', '2026-11-22T09:00:00Z'));
        Assert.areEqual('ignored', r.status);
        Assert.areEqual('Active', [SELECT Status__c FROM Billing_Subscription__c].Status__c);
        Assert.areEqual('Skipped', [SELECT Status__c FROM Integration_Log__c WHERE External_Event_Id__c = 'evt-old'].Status__c);
    }

    @IsTest
    static void unknownAccountIsRejected() {
        String body = event('evt-x', 'subscription.created', 'Active', '2026-11-22T10:00:00Z').replace('A00000042', 'A99999999');
        BillingEventsResource.Result r = BillingEventsResource.handle(body);
        Assert.areEqual(422, r.statusCode);
        Integration_Log__c log = [SELECT Status__c, Error_Category__c FROM Integration_Log__c];
        Assert.areEqual(RetryPolicy.PERMANENT, log.Status__c);
        Assert.areEqual('Validation', log.Error_Category__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Billing_Subscription__c]);
    }

    @IsTest
    static void invalidPayloadsAreRejectedWithoutLogging() {
        List<String> bad = new List<String>{
            null,
            'not json',
            '{}',
            event('evt-1', 'subscription.exploded', 'Active', null),
            event('evt-2', 'subscription.created', 'Bogus', null),
            event('evt-3', 'subscription.created', 'Active', null).replace(SUB_NUMBER, '')
        };
        for (String body : bad) {
            Assert.areEqual(400, BillingEventsResource.handle(body).statusCode, 'body: ' + body);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
    }

    @IsTest
    static void restEndpointWritesJsonResponse() {
        RestContext.request = new RestRequest();
        RestContext.request.requestURI = '/services/apexrest/billing/events';
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestBody = Blob.valueOf(event('evt-rest', 'subscription.created', 'Active', '2026-11-22T10:00:00Z'));
        RestContext.response = new RestResponse();

        BillingEventsResource.receive();

        Assert.areEqual(200, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        Assert.areEqual('processed', body.get('status'));
    }
}
