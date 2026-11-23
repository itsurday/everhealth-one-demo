/**
 * Tests the declarative Q2C automation: EH_Quote_Before_Save, EH_Account_Lifecycle_From_Subscription,
 * EH_Quote_Discount_Approval and the acceptance validation rule. (EH_Renewal_Generator is a scheduled
 * flow, which Apex can't invoke; it is verified in the org per the demo script.)
 */
@IsTest
private class Q2CAutomation_Test {
    @TestSetup
    static void setup() {
        Account acct = TestDataFactory.account('Summit Physical Therapy (fictional)');
        TestDataFactory.quotes(acct, TestDataFactory.recurringProduct('ZSIM-PT'), 1);
    }

    private static Billing_Subscription__c subscription(Id accountId, String num, String status) {
        return new Billing_Subscription__c(
            Name = num,
            Account__c = accountId,
            Subscription_Number__c = num,
            Subscription_Key__c = 'Zuora (Simulated):' + num,
            Status__c = status,
            Term_Start_Date__c = Date.today().addMonths(-11),
            Term_End_Date__c = Date.today().addDays(30)
        );
    }

    private static String lifecycle() {
        return [SELECT Lifecycle_Stage__c FROM Account LIMIT 1].Lifecycle_Stage__c;
    }

    @IsTest
    static void quoteTypeDefaultsFromOpportunityRecordType() {
        Assert.areEqual('New', [SELECT Quote_Type__c FROM Quote LIMIT 1].Quote_Type__c, 'New Business -> New');

        Account acct = [SELECT Id FROM Account LIMIT 1];
        Billing_Subscription__c sub = subscription(acct.Id, 'A-S10000001', 'Active');
        insert sub;
        Opportunity renewal = new Opportunity(Name = 'Renewal', AccountId = acct.Id, StageName = 'Qualification', CloseDate = Date.today().addDays(30),
            RecordTypeId = TestDataFactory.recordTypeId('Renewal'), Source_Subscription__c = sub.Id);
        insert renewal;
        Quote q = new Quote(Name = 'Renewal quote', OpportunityId = renewal.Id);
        insert q;
        Assert.areEqual('Renew', [SELECT Quote_Type__c FROM Quote WHERE Id = :q.Id].Quote_Type__c, 'Renewal -> Renew');
    }

    @IsTest
    static void explicitQuoteTypeIsKept() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Quote q = new Quote(Name = 'Explicit', OpportunityId = opp.Id, Quote_Type__c = 'Amend');
        insert q;
        Assert.areEqual('Amend', [SELECT Quote_Type__c FROM Quote WHERE Id = :q.Id].Quote_Type__c);
    }

    @IsTest
    static void renewalOpportunityNeedsSourceSubscription() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Opportunity renewal = new Opportunity(Name = 'Bad renewal', AccountId = acct.Id, StageName = 'Qualification',
            CloseDate = Date.today(), RecordTypeId = TestDataFactory.recordTypeId('Renewal'));
        Database.SaveResult result = Database.insert(renewal, false);
        Assert.isFalse(result.isSuccess());
        Assert.isTrue(result.getErrors()[0].getMessage().contains('Source Subscription'));
    }

    @IsTest
    static void lifecycleFollowsSubscriptions() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Billing_Subscription__c first = subscription(acct.Id, 'A-S20000001', 'Active');
        Billing_Subscription__c second = subscription(acct.Id, 'A-S20000002', 'Active');
        insert new List<Billing_Subscription__c>{ first, second };
        Assert.areEqual('Customer', lifecycle());

        first.Status__c = 'Cancelled';
        update first;
        Assert.areEqual('Customer', lifecycle(), 'another active subscription remains');

        second.Status__c = 'Expired';
        update second;
        Assert.areEqual('Former Customer', lifecycle());
    }

    @IsTest
    static void suspendedSubscriptionDoesNotChangeLifecycle() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Billing_Subscription__c sub = subscription(acct.Id, 'A-S30000001', 'Active');
        insert sub;
        sub.Status__c = 'Suspended';
        update sub;
        Assert.areEqual('Customer', lifecycle());
    }

    @IsTest
    static void discountAboveThresholdNeedsApprovalBeforeAcceptance() {
        QuoteLineItem line = [SELECT Id FROM QuoteLineItem LIMIT 1];
        line.Discount = 20; // threshold in Q2C_Setting__mdt.Default is 15%
        update line;
        Quote q = [SELECT Id, Requires_Discount_Approval__c FROM Quote LIMIT 1];
        Assert.isTrue(q.Requires_Discount_Approval__c);

        q.Status = 'Accepted';
        Database.SaveResult blocked = Database.update(q, false);
        Assert.isFalse(blocked.isSuccess(), 'VR blocks acceptance before approval');

        Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
        submit.setObjectId(q.Id);
        submit.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
        Approval.ProcessResult submitted = Approval.process(submit);
        Assert.isTrue(submitted.isSuccess());
        Assert.areEqual('Pending', [SELECT Approval_Status__c FROM Quote WHERE Id = :q.Id].Approval_Status__c);

        Approval.ProcessWorkitemRequest approve = new Approval.ProcessWorkitemRequest();
        approve.setWorkitemId(submitted.getNewWorkitemIds()[0]);
        approve.setAction('Approve');
        Assert.isTrue(Approval.process(approve).isSuccess());
        Quote approved = [SELECT Approval_Status__c, Status FROM Quote WHERE Id = :q.Id];
        Assert.areEqual('Approved', approved.Approval_Status__c);
        Assert.areEqual('Approved', approved.Status);

        approved.Status = 'Accepted';
        update approved; // now allowed
        Assert.areEqual('Accepted', [SELECT Status FROM Quote WHERE Id = :q.Id].Status);
    }

    @IsTest
    static void smallDiscountCanBeAcceptedWithoutApproval() {
        Quote q = [SELECT Id, Requires_Discount_Approval__c FROM Quote LIMIT 1];
        Assert.isFalse(q.Requires_Discount_Approval__c);
        q.Status = 'Accepted';
        Assert.isTrue(Database.update(q, false).isSuccess());
    }
}
