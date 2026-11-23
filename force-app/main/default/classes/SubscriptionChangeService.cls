/**
 * Q2C-07: builds an Amendment or Renewal opportunity + quote from an existing subscription, pre-filled with its
 * current recurring charges (from the source quote). The rep then adjusts quantities on the quote.
 * Amendments co-term with the subscription (Zuora-style): the quote runs from today to the current term end.
 * Renewals start the day after term end and reuse the renewal opportunity if EH_Renewal_Generator made one.
 *
 * User-driven, so reads and writes run in USER_MODE. Exception: the renewal opportunity (system-managed
 * Renewal_Key__c) and the subscription link are written in SYSTEM_MODE, as EH_Renewal_Generator does.
 */
public with sharing class SubscriptionChangeService {
    public static final String AMENDMENT = 'Amendment';
    public static final String RENEWAL = 'Renewal';
    private static final Integer RENEWAL_TERM_MONTHS = 12;
    private static final Integer AMENDMENT_CLOSE_DAYS = 30;

    /** Raised with a user-safe message the screen flow shows. */
    public class SubscriptionChangeException extends Exception {}

    /** Flow input. */
    public class Request {
        @InvocableVariable(label='Subscription Id' required=true)
        public Id subscriptionId;
        @InvocableVariable(label='Change Type (Amendment or Renewal)' required=true)
        public String changeType;
    }

    /** Flow output. */
    public class Result {
        @InvocableVariable(label='Opportunity Id')
        public Id opportunityId;
        @InvocableVariable(label='Quote Id')
        public Id quoteId;
        @InvocableVariable(label='Message')
        public String message;
    }

    /** Entry point for the EH_Amend_Renew_Subscription screen flow (one subscription per run). */
    @InvocableMethod(label='Create amendment or renewal quote' description='Pre-fills an Amendment/Renewal opportunity and quote from a subscription.' category='EverHealth One')
    public static List<Result> createFromFlow(List<Request> requests) {
        if (requests.size() != 1) {
            throw new SubscriptionChangeException('Run this for one subscription at a time.');
        }
        return new List<Result>{ create(requests[0].subscriptionId, requests[0].changeType) };
    }

    public static Result create(Id subscriptionId, String changeType) {
        if (changeType != AMENDMENT && changeType != RENEWAL) {
            throw new SubscriptionChangeException('Change type must be Amendment or Renewal.');
        }
        Billing_Subscription__c sub = BillingSubscriptionSelector.forChange(subscriptionId);
        validate(sub);
        List<QuoteLineItem> charges = QuoteSelector.chargesToCarryForward(sub.Source_Quote__c);
        if (charges.isEmpty()) {
            throw new SubscriptionChangeException('The source quote has no recurring or usage charges to carry forward.');
        }

        Opportunity opp = changeType == RENEWAL ? renewalOpportunity(sub) : amendmentOpportunity(sub);
        Quote q = new Quote(
            Name = opp.Name + ' Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = charges[0].Quote.Pricebook2Id,
            Status = 'Draft',
            Term_Start_Date__c = changeType == RENEWAL ? sub.Term_End_Date__c.addDays(1) : Date.today(),
            Term_Months__c = changeType == RENEWAL ? RENEWAL_TERM_MONTHS : Math.max(1, Date.today().monthsBetween(sub.Term_End_Date__c))
        );
        Database.insert(q, AccessLevel.USER_MODE);

        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (QuoteLineItem li : charges) {
            lines.add(new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = li.PricebookEntryId, Quantity = li.Quantity, UnitPrice = li.UnitPrice, Discount = li.Discount));
        }
        Database.insert(lines, AccessLevel.USER_MODE);

        Result r = new Result();
        r.opportunityId = opp.Id;
        r.quoteId = q.Id;
        r.message = changeType + ' quote created with ' + lines.size() + ' current charge(s). Adjust quantities, then submit as usual.';
        return r;
    }

    private static void validate(Billing_Subscription__c sub) {
        if (sub == null) {
            throw new SubscriptionChangeException('Subscription not found or not visible to you.');
        }
        if (sub.Status__c != 'Active') {
            throw new SubscriptionChangeException('Only active subscriptions can be amended or renewed.');
        }
        if (sub.Source_Quote__c == null) {
            throw new SubscriptionChangeException('This subscription has no source quote to copy charges from; build the quote manually.');
        }
        if (sub.Term_End_Date__c == null) {
            throw new SubscriptionChangeException('This subscription has no term end date (evergreen); amend it manually.');
        }
    }

    private static Opportunity amendmentOpportunity(Billing_Subscription__c sub) {
        Opportunity opp = new Opportunity(
            Name = sub.Account__r.Name + ' - Amendment ' + Date.today().format(),
            AccountId = sub.Account__c,
            RecordTypeId = recordTypeId(AMENDMENT),
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(AMENDMENT_CLOSE_DAYS),
            Source_Subscription__c = sub.Id
        );
        Database.insert(opp, AccessLevel.USER_MODE);
        return opp;
    }

    private static Opportunity renewalOpportunity(Billing_Subscription__c sub) {
        if (sub.Renewal_Opportunity__c != null) {
            return OpportunitySelector.byId(sub.Renewal_Opportunity__c);
        }
        Opportunity opp = new Opportunity(
            Name = sub.Account__r.Name + ' - Renewal ' + sub.Term_End_Date__c.year(),
            AccountId = sub.Account__c,
            RecordTypeId = recordTypeId(RENEWAL),
            StageName = 'Qualification',
            CloseDate = sub.Term_End_Date__c,
            Source_Subscription__c = sub.Id,
            Renewal_Key__c = sub.Subscription_Key__c + ':' + String.valueOf(sub.Term_End_Date__c) // same format as EH_Renewal_Generator
        );
        Database.insert(opp, AccessLevel.SYSTEM_MODE);
        Database.update(new Billing_Subscription__c(Id = sub.Id, Renewal_Opportunity__c = opp.Id), AccessLevel.SYSTEM_MODE);
        return opp;
    }

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }
}
