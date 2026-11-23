@IsTest
private class SubscriptionChangeService_Test {
    @TestSetup
    static void setup() {
        Account acct = TestDataFactory.account('Harbor Behavioral Health (fictional)');
        PricebookEntry platform = TestDataFactory.recurringProduct('ZSIM-PLATFORM');
        Quote source = TestDataFactory.quotes(acct, platform, 1)[0];

        // add a one-time charge that must NOT be carried into an amendment/renewal
        Product2 onboarding = new Product2(Name = 'Onboarding', IsActive = true, Charge_Type__c = 'One-Time', Charge_Model__c = 'Flat Fee', Billing_Charge_Id__c = 'ZSIM-ONB');
        insert onboarding;
        PricebookEntry onbEntry = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = onboarding.Id, UnitPrice = 2500, IsActive = true);
        insert onbEntry;
        insert new QuoteLineItem(QuoteId = source.Id, PricebookEntryId = onbEntry.Id, Quantity = 1, UnitPrice = 2500, Discount = 0);

        insert new Billing_Subscription__c(
            Name = 'A-S40000001', Account__c = acct.Id, Subscription_Number__c = 'A-S40000001',
            Subscription_Key__c = 'Zuora (Simulated):A-S40000001', Status__c = 'Active', MRR__c = 200,
            Term_Start_Date__c = Date.today().addMonths(-6), Term_End_Date__c = Date.today().addMonths(6).addDays(-1),
            Source_Quote__c = source.Id
        );
    }

    private static Billing_Subscription__c sub() {
        return [SELECT Id, Term_End_Date__c, Renewal_Opportunity__c, Subscription_Key__c FROM Billing_Subscription__c LIMIT 1];
    }

    @IsTest
    static void amendmentCoTermsAndCarriesRecurringCharges() {
        Billing_Subscription__c s = sub();
        Test.startTest();
        SubscriptionChangeService.Result r = SubscriptionChangeService.create(s.Id, SubscriptionChangeService.AMENDMENT);
        Test.stopTest();

        Opportunity opp = [SELECT RecordType.DeveloperName, Source_Subscription__c, StageName, Renewal_Key__c FROM Opportunity WHERE Id = :r.opportunityId];
        Assert.areEqual('Amendment', opp.RecordType.DeveloperName);
        Assert.areEqual(s.Id, opp.Source_Subscription__c);
        Assert.isNull(opp.Renewal_Key__c, 'amendments have no renewal key');

        Quote q = [SELECT Quote_Type__c, Term_Start_Date__c, Term_Months__c, (SELECT Product2.Charge_Type__c, Quantity FROM QuoteLineItems) FROM Quote WHERE Id = :r.quoteId];
        Assert.areEqual('Amend', q.Quote_Type__c, 'quote type defaulted by EH_Quote_Before_Save');
        Assert.areEqual(Date.today(), q.Term_Start_Date__c);
        Assert.areEqual(Date.today().monthsBetween(s.Term_End_Date__c), q.Term_Months__c, 'co-termed to the current term end');
        Assert.areEqual(1, q.QuoteLineItems.size(), 'one-time onboarding not carried forward');
        Assert.areEqual('Recurring', q.QuoteLineItems[0].Product2.Charge_Type__c);
        Assert.areEqual(2, q.QuoteLineItems[0].Quantity);
    }

    @IsTest
    static void renewalCreatesOneLinkedOpportunityAndReusesIt() {
        Billing_Subscription__c s = sub();
        SubscriptionChangeService.Result first = SubscriptionChangeService.create(s.Id, SubscriptionChangeService.RENEWAL);
        SubscriptionChangeService.Result second = SubscriptionChangeService.create(s.Id, SubscriptionChangeService.RENEWAL);

        Assert.areEqual(first.opportunityId, second.opportunityId, 'second renewal quote goes on the same renewal opportunity');
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity WHERE RecordType.DeveloperName = 'Renewal']);
        Opportunity opp = [SELECT Renewal_Key__c, CloseDate FROM Opportunity WHERE Id = :first.opportunityId];
        Assert.areEqual(s.Subscription_Key__c + ':' + String.valueOf(s.Term_End_Date__c), opp.Renewal_Key__c, 'same key format as EH_Renewal_Generator');
        Assert.areEqual(s.Term_End_Date__c, opp.CloseDate);
        Assert.areEqual(first.opportunityId, sub().Renewal_Opportunity__c);

        Quote q = [SELECT Quote_Type__c, Term_Start_Date__c, Term_Months__c FROM Quote WHERE Id = :first.quoteId];
        Assert.areEqual('Renew', q.Quote_Type__c);
        Assert.areEqual(s.Term_End_Date__c.addDays(1), q.Term_Start_Date__c);
        Assert.areEqual(12, q.Term_Months__c);
    }

    @IsTest
    static void renewalUsesOpportunityFromTheGenerator() {
        Billing_Subscription__c s = sub();
        Opportunity generated = new Opportunity(Name = 'Generated renewal', AccountId = [SELECT Id FROM Account LIMIT 1].Id, StageName = 'Qualification',
            CloseDate = s.Term_End_Date__c, RecordTypeId = TestDataFactory.recordTypeId('Renewal'), Source_Subscription__c = s.Id);
        insert generated;
        update new Billing_Subscription__c(Id = s.Id, Renewal_Opportunity__c = generated.Id);

        SubscriptionChangeService.Result r = SubscriptionChangeService.create(s.Id, SubscriptionChangeService.RENEWAL);
        Assert.areEqual(generated.Id, r.opportunityId);
    }

    @IsTest
    static void salesUserCanAmendFromTheFlowAction() {
        User sales = TestDataFactory.user('ehamend', new List<String>{ 'EH_Sales_User' });
        // Account OWD is Private: give the rep access to the account, as account ownership/teams would in the org
        insert new AccountShare(AccountId = [SELECT Id FROM Account LIMIT 1].Id, UserOrGroupId = sales.Id,
            AccountAccessLevel = 'Edit', OpportunityAccessLevel = 'Edit');
        SubscriptionChangeService.Request req = new SubscriptionChangeService.Request();
        req.subscriptionId = sub().Id;
        req.changeType = SubscriptionChangeService.AMENDMENT;
        List<SubscriptionChangeService.Result> results;
        System.runAs(sales) {
            results = SubscriptionChangeService.createFromFlow(new List<SubscriptionChangeService.Request>{ req });
        }
        Assert.isNotNull(results[0].quoteId);
        Assert.isTrue(results[0].message.contains('Amendment'), results[0].message);
    }

    @IsTest
    static void rejectsBadRequests() {
        Billing_Subscription__c s = sub();
        assertFails(s.Id, 'Upgrade', 'Change type');

        update new Billing_Subscription__c(Id = s.Id, Status__c = 'Cancelled');
        assertFails(s.Id, SubscriptionChangeService.AMENDMENT, 'active');

        update new Billing_Subscription__c(Id = s.Id, Status__c = 'Active', Source_Quote__c = null);
        assertFails(s.Id, SubscriptionChangeService.RENEWAL, 'source quote');
    }

    private static void assertFails(Id subscriptionId, String changeType, String expectedText) {
        try {
            SubscriptionChangeService.create(subscriptionId, changeType);
            Assert.fail('expected failure containing: ' + expectedText);
        } catch (SubscriptionChangeService.SubscriptionChangeException e) {
            Assert.isTrue(e.getMessage().contains(expectedText), e.getMessage());
        }
    }
}
