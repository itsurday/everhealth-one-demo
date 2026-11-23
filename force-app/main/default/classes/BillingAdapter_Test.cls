@IsTest
private class BillingAdapter_Test {
    private static BillingAdapter.Request request(String key) {
        BillingAdapter.Request r = new BillingAdapter.Request();
        r.idempotencyKey = key;
        r.accountId = '001000000000001AAA';
        r.termMonths = 12;
        r.termStartDate = Date.newInstance(2026, 1, 1);
        BillingAdapter.Line monthly = new BillingAdapter.Line();
        monthly.chargeType = 'Recurring';
        monthly.billingPeriod = 'Month';
        monthly.quantity = 2;
        monthly.unitPrice = 100;
        monthly.discountPercent = 10;
        BillingAdapter.Line annual = new BillingAdapter.Line();
        annual.chargeType = 'Recurring';
        annual.billingPeriod = 'Annual';
        annual.quantity = 1;
        annual.unitPrice = 1200;
        BillingAdapter.Line oneTime = new BillingAdapter.Line();
        oneTime.chargeType = 'One-Time';
        oneTime.quantity = 1;
        oneTime.unitPrice = 500;
        r.lines.addAll(new List<BillingAdapter.Line>{ monthly, annual, oneTime });
        return r;
    }

    @IsTest
    static void stubSucceedsDeterministically() {
        BillingAdapter.Response a = new StubBillingAdapter('None').createSubscription(request('SF:QUOTE_SYNC:1'));
        BillingAdapter.Response b = new StubBillingAdapter(null).createSubscription(request('SF:QUOTE_SYNC:1'));
        Assert.isTrue(a.success);
        Assert.areEqual(201, a.httpStatus);
        Assert.areEqual(a.subscriptionNumber, b.subscriptionNumber, 'same idempotency key -> same subscription');
        Assert.isTrue(Pattern.matches('A-S[0-9]{8}', a.subscriptionNumber), a.subscriptionNumber);
        Assert.isTrue(Pattern.matches('A[0-9]{8}', a.accountNumber), a.accountNumber);
        Assert.areEqual(Date.newInstance(2026, 12, 31), a.termEndDate);
        // MRR: 2*100*0.9 monthly + 1200/12 annual; one-time excluded
        Assert.areEqual(280.00, a.mrr);
    }

    @IsTest
    static void stubReusesExistingBillingAccount() {
        BillingAdapter.Request r = request('k');
        r.billingAccountNumber = 'A12345678';
        Assert.areEqual('A12345678', new StubBillingAdapter('None').createSubscription(r).accountNumber);
    }

    @IsTest
    static void stubFailModes() {
        Map<String, Integer> expected = new Map<String, Integer>{ 'Timeout' => 504, 'RateLimit' => 429, 'Validation' => 400 };
        for (String mode : expected.keySet()) {
            BillingAdapter.Response res = new StubBillingAdapter(mode).createSubscription(request('k'));
            Assert.isFalse(res.success, mode);
            Assert.areEqual(expected.get(mode), res.httpStatus, mode);
            Assert.isTrue(res.errorMessage.contains('simulated'), mode);
        }
    }

    @IsTest
    static void stubRejectsMissingTermStart() {
        BillingAdapter.Request r = request('k');
        r.termStartDate = null;
        BillingAdapter.Response res = new StubBillingAdapter('None').createSubscription(r);
        Assert.isFalse(res.success);
        Assert.areEqual(400, res.httpStatus);
    }

    private class MockHttp implements HttpCalloutMock {
        private final Integer status;
        private final String body;
        private final Boolean throwError;
        MockHttp(Integer status, String body, Boolean throwError) {
            this.status = status;
            this.body = body;
            this.throwError = throwError;
        }
        public HttpResponse respond(HttpRequest req) {
            Assert.areEqual('callout:Zuora_Billing/v1/subscriptions', req.getEndpoint());
            Assert.areEqual('k', req.getHeader('Idempotency-Key'));
            if (throwError) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    @IsTest
    static void httpAdapterParsesSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockHttp(201, '{"subscriptionNumber":"A-S00000001","accountNumber":"A00000001","version":1,"status":"Active"}', false));
        BillingAdapter.Response res = new HttpBillingAdapter('Zuora_Billing', 10000).createSubscription(request('k'));
        Assert.isTrue(res.success);
        Assert.areEqual('A-S00000001', res.subscriptionNumber);
        Assert.areEqual(201, res.httpStatus);
    }

    @IsTest
    static void httpAdapterReportsErrorsWithoutBody() {
        Test.setMock(HttpCalloutMock.class, new MockHttp(429, '{"secret":"do-not-log"}', false));
        BillingAdapter.Response res = new HttpBillingAdapter('Zuora_Billing', 10000).createSubscription(request('k'));
        Assert.isFalse(res.success);
        Assert.areEqual(429, res.httpStatus);
        Assert.isFalse(res.errorMessage.contains('do-not-log'), 'response body must not be logged');
    }

    @IsTest
    static void httpAdapterMapsCalloutExceptionToStatusZero() {
        Test.setMock(HttpCalloutMock.class, new MockHttp(0, null, true));
        BillingAdapter.Response res = new HttpBillingAdapter('Zuora_Billing', 10000).createSubscription(request('k'));
        Assert.isFalse(res.success);
        Assert.areEqual(0, res.httpStatus);
    }

    @IsTest
    static void stubCommitWorkPersistsAndGetSubscriptionsReadsBack() {
        StubBillingAdapter stub = new StubBillingAdapter('None');
        BillingAdapter.Response created = stub.createSubscription(request('SF:QUOTE_SYNC:2'));
        stub.commitWork();
        Map<String, BillingAdapter.Response> view = stub.getSubscriptions(new Set<String>{ created.subscriptionNumber, 'A-S00000000' });
        Assert.areEqual(1, view.size(), 'unknown numbers are simply absent');
        Assert.areEqual(280.00, view.get(created.subscriptionNumber).mrr);
        Assert.areEqual('Active', view.get(created.subscriptionNumber).status);
    }

    private class GetMock implements HttpCalloutMock {
        private final Integer status;
        GetMock(Integer status) {
            this.status = status;
        }
        public HttpResponse respond(HttpRequest req) {
            Assert.areEqual('GET', req.getMethod());
            Assert.isTrue(req.getEndpoint().startsWith('callout:Zuora_Billing/v1/subscriptions?numbers='), req.getEndpoint());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody('[{"subscriptionNumber":"A-S1","status":"Active","mrr":10}]');
            return res;
        }
    }

    @IsTest
    static void httpGetSubscriptionsParsesAndFailsLoudly() {
        Test.setMock(HttpCalloutMock.class, new GetMock(200));
        Map<String, BillingAdapter.Response> view = new HttpBillingAdapter('Zuora_Billing', 10000).getSubscriptions(new Set<String>{ 'A-S1' });
        Assert.areEqual(10, view.get('A-S1').mrr);

        Test.setMock(HttpCalloutMock.class, new GetMock(503));
        try {
            new HttpBillingAdapter('Zuora_Billing', 10000).getSubscriptions(new Set<String>{ 'A-S1' });
            Assert.fail('an outage must not look like "missing in billing"');
        } catch (BillingSyncService.BillingSyncException e) {
            Assert.isTrue(e.getMessage().contains('503'));
        }
    }

    @IsTest
    static void factoryPicksAdapterFromConfig() {
        Integration_Config__mdt cfg = TestDataFactory.config('None', true);
        Assert.isInstanceOfType(BillingAdapterFactory.create(cfg), StubBillingAdapter.class);
        cfg.Mode__c = 'NamedCredential';
        cfg.Named_Credential__c = 'Zuora_Billing';
        Assert.isInstanceOfType(BillingAdapterFactory.create(cfg), HttpBillingAdapter.class);
        Assert.isNotNull(BillingAdapterFactory.config(), 'deployed Zuora_Billing record exists');
    }
}
