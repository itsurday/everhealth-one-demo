// EverHealth One demo seed, part 4: reconciliation (SYNC-07).
// 1) Backfill the simulated Zuora store for subscriptions created before it existed (idempotent).
// 2) Plant one drift: Pinecrest got a price uplift "directly in Zuora" (+75 MRR), only if no drift exists yet.
// 3) Run reconciliation now (stub mode: no callouts) so the mismatch shows on the Sync Health dashboard.

Set<String> existing = new Set<String>();
for (Zuora_Subscription_Sim__c z : [SELECT Subscription_Number__c FROM Zuora_Subscription_Sim__c]) { existing.add(z.Subscription_Number__c); }
List<Zuora_Subscription_Sim__c> backfill = new List<Zuora_Subscription_Sim__c>();
for (Billing_Subscription__c s : [SELECT Subscription_Number__c, Billing_Account_Number__c, Status__c, Term_End_Date__c, MRR__c, Version__c FROM Billing_Subscription__c]) {
    if (!existing.contains(s.Subscription_Number__c)) {
        backfill.add(new Zuora_Subscription_Sim__c(Name = s.Subscription_Number__c, Subscription_Number__c = s.Subscription_Number__c,
            Account_Number__c = s.Billing_Account_Number__c, Status__c = s.Status__c, Term_End_Date__c = s.Term_End_Date__c, MRR__c = s.MRR__c, Version__c = s.Version__c));
    }
}
insert backfill;

List<Billing_Subscription__c> pinecrest = [SELECT Subscription_Number__c, MRR__c FROM Billing_Subscription__c WHERE Account__r.Account_Key__c = 'ACC-0005' LIMIT 1];
Boolean planted = false;
if (!pinecrest.isEmpty()) {
    Zuora_Subscription_Sim__c z = [SELECT Id, MRR__c FROM Zuora_Subscription_Sim__c WHERE Subscription_Number__c = :pinecrest[0].Subscription_Number__c];
    if (z.MRR__c == pinecrest[0].MRR__c) {
        z.MRR__c = pinecrest[0].MRR__c + 75;
        update z;
        planted = true;
    }
}
Integer mismatches = BillingReconciliationJob.run();
System.debug('SEED4: backfilled ' + backfill.size() + ', drift planted ' + planted + ', mismatches ' + mismatches);
