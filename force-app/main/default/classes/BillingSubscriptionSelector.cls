/**
 * Billing_Subscription__c (and billing-account Account) queries. Integration queries run in system mode on purpose; user-driven queries use USER_MODE.
 */
public inherited sharing class BillingSubscriptionSelector {
    /** Subscriptions keyed by Subscription_Key__c. */
    public static Map<String, Billing_Subscription__c> byKeys(Set<String> keys) {
        Map<String, Billing_Subscription__c> out = new Map<String, Billing_Subscription__c>();
        for (Billing_Subscription__c s : [
            SELECT Id, Account__c, Subscription_Key__c, External_Updated_At__c
            FROM Billing_Subscription__c
            WHERE Subscription_Key__c IN :keys
            WITH SYSTEM_MODE
        ]) {
            out.put(s.Subscription_Key__c, s);
        }
        return out;
    }

    /** One subscription for the amend/renew action. User-driven: USER_MODE. Returns null if not visible. */
    public static Billing_Subscription__c forChange(Id subscriptionId) {
        List<Billing_Subscription__c> rows = [
            SELECT Id, Account__c, Account__r.Name, Status__c, Term_End_Date__c, Subscription_Key__c, Source_Quote__c, Renewal_Opportunity__c
            FROM Billing_Subscription__c
            WHERE Id = :subscriptionId
            WITH USER_MODE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Simulated Zuora records (stub adapter only). */
    public static List<Zuora_Subscription_Sim__c> simulatedZuora(Set<String> numbers) {
        return [
            SELECT Subscription_Number__c, Account_Number__c, Status__c, Term_End_Date__c, MRR__c, Version__c
            FROM Zuora_Subscription_Sim__c
            WHERE Subscription_Number__c IN :numbers
            WITH SYSTEM_MODE
        ];
    }

    /** Subscriptions to reconcile against billing, oldest first. */
    public static List<Billing_Subscription__c> forReconciliation(Integer maxRows) {
        return [
            SELECT Id, Account__c, Subscription_Number__c, Status__c, MRR__c, Term_End_Date__c
            FROM Billing_Subscription__c
            WHERE Subscription_Number__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT :maxRows
        ];
    }

    /** Account Ids keyed by Billing_Account_Number__c (Zuora account number, simulated). */
    public static Map<String, Id> accountIdsByBillingNumber(Set<String> numbers) {
        Map<String, Id> out = new Map<String, Id>();
        for (Account a : [SELECT Id, Billing_Account_Number__c FROM Account WHERE Billing_Account_Number__c IN :numbers WITH SYSTEM_MODE]) {
            out.put(a.Billing_Account_Number__c, a.Id);
        }
        return out;
    }
}
