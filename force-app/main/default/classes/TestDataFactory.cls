/**
 * Test data for EverHealth One. Synthetic only: fictional practices, example.com addresses.
 */
@IsTest
public class TestDataFactory {
    public static Account account(String name) {
        Account a = new Account(
            Name = name,
            Website = 'https://example.com',
            Phone = '555-0100',
            BillingCountry = 'US',
            Practice_Type__c = 'Dental'
        );
        insert a;
        return a;
    }

    public static PricebookEntry recurringProduct(String chargeId) {
        Product2 p = new Product2(
            Name = 'Practice Platform ' + chargeId,
            IsActive = true,
            Charge_Type__c = 'Recurring',
            Charge_Model__c = 'Flat Fee',
            Billing_Period__c = 'Month',
            Billing_Charge_Id__c = chargeId
        );
        insert p;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = p.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    /** Creates one New Business opportunity with {count} draft quotes, each with one line (qty 2 x 100, no discount). */
    public static List<Quote> quotes(Account acct, PricebookEntry pbe, Integer count) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = recordTypeId('New_Business'),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opp;

        List<Quote> quotes = new List<Quote>();
        for (Integer i = 0; i < count; i++) {
            quotes.add(new Quote(
                Name = 'Q' + i,
                OpportunityId = opp.Id,
                Pricebook2Id = Test.getStandardPricebookId(),
                Status = 'Draft',
                Term_Months__c = 12,
                Term_Start_Date__c = Date.today()
            ));
        }
        insert quotes;

        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (Quote q : quotes) {
            lines.add(new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 2, UnitPrice = 100, Discount = 0));
        }
        insert lines;
        return quotes;
    }

    public static void accept(List<Quote> quotes) {
        for (Quote q : quotes) {
            q.Status = 'Accepted';
        }
        update quotes;
    }

    public static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    /** In-memory config record (CMDT can't be inserted in tests). */
    public static Integration_Config__mdt config(String failMode, Boolean active) {
        return (Integration_Config__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Zuora_Billing',
            'Is_Active__c' => active,
            'Mode__c' => 'Stub',
            'Fail_Mode__c' => failMode,
            'Max_Attempts__c' => 3,
            'Base_Backoff_Seconds__c' => 60,
            'Timeout_Ms__c' => 10000
        }), Integration_Config__mdt.class);
    }

    /** Standard User with the given permission sets. Runs as the current user to avoid mixed-DML errors. */
    public static User user(String alias, List<String> permissionSets) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            u = new User(
                Alias = alias,
                LastName = 'Test ' + alias,
                Email = alias + '@example.com',
                Username = alias + '.' + System.currentTimeMillis() + '@eh-test.example.com',
                ProfileId = p.Id,
                TimeZoneSidKey = 'America/Chicago',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            insert u;
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :permissionSets]) {
                psas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert psas;
        }
        return u;
    }
}
