/**
 * In-org stand-in for Zuora Billing. SIMULATED: no external system is called.
 * Fail_Mode__c (None / Timeout / RateLimit / Validation) makes it fail on demand for the live failure demo.
 */
public with sharing class StubBillingAdapter extends BillingAdapter {
    private final String failMode;
    private final List<Zuora_Subscription_Sim__c> pending = new List<Zuora_Subscription_Sim__c>();

    public StubBillingAdapter(String failMode) {
        this.failMode = String.isBlank(failMode) ? 'None' : failMode;
    }

    public override Response createSubscription(Request request) {
        Response res = new Response();
        switch on failMode {
            when 'Timeout' {
                return fail(res, 504, 'Gateway timeout from billing (simulated)');
            }
            when 'RateLimit' {
                return fail(res, 429, 'Too many requests, retry later (simulated)');
            }
            when 'Validation' {
                return fail(res, 400, 'Invalid subscription request: unknown charge (simulated)');
            }
        }
        if (request.termStartDate == null || request.termMonths == null) {
            return fail(res, 400, 'Term start date and term months are required (simulated)');
        }
        res.success = true;
        res.httpStatus = 201;
        res.accountNumber = String.isNotBlank(request.billingAccountNumber)
            ? request.billingAccountNumber
            : 'A' + digits(String.valueOf(request.accountId), 8);
        res.subscriptionNumber = 'A-S' + digits(request.idempotencyKey, 8);
        res.version = 1;
        res.status = 'Active';
        res.termStartDate = request.termStartDate;
        res.termEndDate = request.termStartDate.addMonths(request.termMonths).addDays(-1);
        res.mrr = monthlyRecurring(request.lines);
        pending.add(toSim(res));
        return res;
    }

    public override Map<String, Response> getSubscriptions(Set<String> subscriptionNumbers) {
        Map<String, Response> out = new Map<String, Response>();
        for (Zuora_Subscription_Sim__c z : BillingSubscriptionSelector.simulatedZuora(subscriptionNumbers)) {
            Response r = new Response();
            r.success = true;
            r.httpStatus = 200;
            r.subscriptionNumber = z.Subscription_Number__c;
            r.accountNumber = z.Account_Number__c;
            r.status = z.Status__c;
            r.termEndDate = z.Term_End_Date__c;
            r.mrr = z.MRR__c;
            r.version = z.Version__c?.intValue();
            out.put(z.Subscription_Number__c, r);
        }
        return out;
    }

    /** Persists the simulated Zuora records created in this transaction. */
    public override void commitWork() {
        if (!pending.isEmpty()) {
            Database.upsert(pending, Zuora_Subscription_Sim__c.Subscription_Number__c, true, AccessLevel.SYSTEM_MODE);
            pending.clear();
        }
    }

    /**
     * Keeps the simulated Zuora store in step with billing events. In real life events come FROM Zuora, which already
     * holds that state; in this simulation events are sent by hand, so the stub mirrors what they say.
     */
    public static void mirror(Billing_Subscription__c applied) {
        Zuora_Subscription_Sim__c z = new Zuora_Subscription_Sim__c(Name = applied.Subscription_Number__c, Subscription_Number__c = applied.Subscription_Number__c);
        if (applied.Status__c != null) { z.Status__c = applied.Status__c; }
        if (applied.MRR__c != null) { z.MRR__c = applied.MRR__c; }
        if (applied.Term_End_Date__c != null) { z.Term_End_Date__c = applied.Term_End_Date__c; }
        if (applied.Billing_Account_Number__c != null) { z.Account_Number__c = applied.Billing_Account_Number__c; }
        if (applied.Version__c != null) { z.Version__c = applied.Version__c; }
        Database.upsert(z, Zuora_Subscription_Sim__c.Subscription_Number__c, true, AccessLevel.SYSTEM_MODE);
    }

    private static Zuora_Subscription_Sim__c toSim(Response res) {
        return new Zuora_Subscription_Sim__c(Name = res.subscriptionNumber, Subscription_Number__c = res.subscriptionNumber,
            Account_Number__c = res.accountNumber, Status__c = res.status, Term_End_Date__c = res.termEndDate, MRR__c = res.mrr, Version__c = res.version);
    }

    private static Response fail(Response res, Integer status, String message) {
        res.httpStatus = status;
        res.errorMessage = message;
        return res;
    }

    // Deterministic, so the same idempotency key always returns the same number (like an idempotent create).
    private static String digits(String seed, Integer length) {
        String hex = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed ?? '')));
        List<String> out = new List<String>();
        for (Integer i = 0; out.size() < length; i++) {
            out.add(String.valueOf(Math.mod(hex.charAt(i), 10)));
        }
        return String.join(out, '');
    }
}
