// EverHealth One demo seed, part 2 of 2: needs the subscriptions created by part 1's async sync.
// Amendments plus inbound billing events (incl. a duplicate and an unknown account). Idempotent: skips if the seeded amendments exist.

final String MARK = 'EverHealth One demo seed';
Id amendment = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Amendment').getRecordTypeId();

if ([SELECT COUNT() FROM Opportunity WHERE RecordTypeId = :amendment AND Account.Account_Key__c IN ('ACC-0002', 'ACC-0004')] > 0) {
    System.debug('SEED2: already seeded, nothing to do');
} else {
    Map<String, Billing_Subscription__c> subByAccount = new Map<String, Billing_Subscription__c>();
    for (Billing_Subscription__c s : [SELECT Id, Name, Account__c, Account__r.Name, Account__r.Account_Key__c FROM Billing_Subscription__c]) {
        subByAccount.put(s.Account__r.Account_Key__c, s);
    }
    for (String key : new List<String>{ 'ACC-0001', 'ACC-0002', 'ACC-0003', 'ACC-0004' }) {
        if (!subByAccount.containsKey(key)) {
            throw new IllegalArgumentException('Subscription for ' + key + ' not synced yet; rerun part 2 in a minute.');
        }
    }
    Pricebook2 std = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
    Map<String, PricebookEntry> entries = new Map<String, PricebookEntry>();
    for (PricebookEntry e : [SELECT Id, UnitPrice, Product2.Billing_Charge_Id__c FROM PricebookEntry WHERE Pricebook2Id = :std.Id]) {
        entries.put(e.Product2.Billing_Charge_Id__c, e);
    }

    // Harbor: open amendment adding the patient portal. Riverbend: accepted amendment whose sync failed validation.
    Billing_Subscription__c harbor = subByAccount.get('ACC-0004');
    Billing_Subscription__c riverbend = subByAccount.get('ACC-0002');
    List<Opportunity> opps = new List<Opportunity>{
        new Opportunity(Name = harbor.Account__r.Name + ' - Add Patient Portal', AccountId = harbor.Account__c, RecordTypeId = amendment,
            StageName = 'Proposal/Price Quote', CloseDate = Date.today().addDays(14), Source_Subscription__c = harbor.Id, Pricebook2Id = std.Id, Description = MARK),
        new Opportunity(Name = riverbend.Account__r.Name + ' - Add Analytics', AccountId = riverbend.Account__c, RecordTypeId = amendment,
            StageName = 'Closed Won', CloseDate = Date.today(), Source_Subscription__c = riverbend.Id, Pricebook2Id = std.Id, Description = MARK)
    };
    insert opps;
    List<Quote> quotes = new List<Quote>{
        new Quote(Name = opps[0].Name + ' Quote', OpportunityId = opps[0].Id, Pricebook2Id = std.Id, Status = 'Draft', Term_Months__c = 12, Term_Start_Date__c = Date.today().addDays(14)),
        new Quote(Name = opps[1].Name + ' Quote', OpportunityId = opps[1].Id, Pricebook2Id = std.Id, Status = 'Draft', Term_Months__c = 12, Term_Start_Date__c = Date.today())
    };
    insert quotes;
    insert new List<QuoteLineItem>{
        new QuoteLineItem(QuoteId = quotes[0].Id, PricebookEntryId = entries.get('ZSIM-PORTAL').Id, Quantity = 1, UnitPrice = entries.get('ZSIM-PORTAL').UnitPrice, Discount = 0),
        new QuoteLineItem(QuoteId = quotes[1].Id, PricebookEntryId = entries.get('ZSIM-ANALYTICS').Id, Quantity = 1, UnitPrice = entries.get('ZSIM-ANALYTICS').UnitPrice, Discount = 0)
    };
    Integration_Log__c validation = new Integration_Log__c(
        External_Event_Key__c = 'SF:QUOTE_SYNC:' + quotes[1].Id, Event_Type__c = 'quote.sync', Direction__c = 'Outbound',
        Source_System__c = 'Salesforce', Target_System__c = 'Zuora (Simulated)', Correlation_Id__c = UUID.randomUUID().toString(),
        Related_Quote__c = quotes[1].Id, Related_Account__c = riverbend.Account__c, Status__c = 'Permanent Failure',
        Attempt_Count__c = 1, HTTP_Status__c = 400, Error_Category__c = 'Validation',
        Sanitized_Error__c = 'Validation: Invalid subscription request: unknown charge (simulated)', Last_Attempt_At__c = System.now().addHours(-5)
    );
    insert validation;
    update new Quote(Id = quotes[1].Id, Status = 'Accepted');
    update new Quote(Id = quotes[1].Id, Billing_Sync_Status__c = 'Failed', Last_Sync_Log__c = validation.Id);

    // Inbound billing events through the same service the REST endpoint uses.
    String invoice = '{"eventId":"%ID%","eventType":"invoice.posted","occurredAt":"%TS%","subscription":{"subscriptionNumber":"%SUB%"},"invoice":{"status":"Posted"}}';
    String ts = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    String lakeside = invoice.replace('%ID%', 'evt-seed-1001').replace('%TS%', ts).replace('%SUB%', subByAccount.get('ACC-0001').Name);
    BillingEventsResource.handle(lakeside);
    BillingEventsResource.handle(lakeside); // duplicate delivery -> recorded once, Duplicate_Count__c = 1
    BillingEventsResource.handle(invoice.replace('%ID%', 'evt-seed-1002').replace('%TS%', ts).replace('%SUB%', subByAccount.get('ACC-0003').Name));
    BillingEventsResource.handle('{"eventId":"evt-seed-1003","eventType":"subscription.created","occurredAt":"' + ts
        + '","subscription":{"subscriptionNumber":"A-S99999999","accountNumber":"A99999999","status":"Active"}}'); // unknown account -> 422

    System.debug('SEED2: amendments + 4 billing events');
}
