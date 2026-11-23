/**
 * Quote queries. Integration queries run in system mode on purpose; user-driven queries use USER_MODE.
 */
public inherited sharing class QuoteSelector {
    public static Map<Id, Quote> accountIdsByQuote(Set<Id> quoteIds) {
        return new Map<Id, Quote>([SELECT Id, AccountId FROM Quote WHERE Id IN :quoteIds WITH SYSTEM_MODE]);
    }

    /** Recurring and usage lines of a quote (one-time charges aren't carried into amendments/renewals). User-driven: USER_MODE. */
    public static List<QuoteLineItem> chargesToCarryForward(Id quoteId) {
        return [
            SELECT Quantity, UnitPrice, Discount, PricebookEntryId, Quote.Pricebook2Id
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId AND Product2.Charge_Type__c IN ('Recurring', 'Usage')
            WITH USER_MODE
            ORDER BY CreatedDate
        ];
    }

    public static Map<Id, Quote> byIdsWithLines(Set<Id> quoteIds) {
        return new Map<Id, Quote>([
            SELECT Id, QuoteNumber, Quote_Type__c, Term_Months__c, Term_Start_Date__c,
                AccountId, Account.Name, Account.Billing_Account_Number__c,
                (SELECT Quantity, UnitPrice, Discount, Product2.Name, Product2.Billing_Charge_Id__c,
                        Product2.Charge_Type__c, Product2.Billing_Period__c
                 FROM QuoteLineItems)
            FROM Quote
            WHERE Id IN :quoteIds
            WITH SYSTEM_MODE
        ]);
    }
}
