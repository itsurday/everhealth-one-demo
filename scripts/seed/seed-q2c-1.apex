// EverHealth One demo seed, part 1 of 2: pricebook, deals, quotes, acceptance (real sync path).
// Idempotent: does nothing if the seeded New Business deal for ACC-0001 already exists. Synthetic data only (fictional practices).
// Run after the CSV upserts (accounts, contacts, leads, products).

final String MARK = 'EverHealth One demo seed';
final Map<String, Decimal> PRICES = new Map<String, Decimal>{
    'ZSIM-PLAT-BASE' => 499, 'ZSIM-PROV-SEAT' => 89, 'ZSIM-ECLAIMS' => 0.35,
    'ZSIM-ONBOARD' => 2500, 'ZSIM-PORTAL' => 149, 'ZSIM-ANALYTICS' => 1200
};

if ([SELECT COUNT() FROM Opportunity WHERE Account.Account_Key__c = 'ACC-0001' AND RecordType.DeveloperName = 'New_Business'] > 0) {
    System.debug('SEED1: already seeded, nothing to do');
} else {
    Pricebook2 std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
    if (!std.IsActive) { std.IsActive = true; update std; }

    Map<String, Id> productByCharge = new Map<String, Id>();
    for (Product2 p : [SELECT Id, Billing_Charge_Id__c FROM Product2 WHERE Billing_Charge_Id__c IN :PRICES.keySet()]) {
        productByCharge.put(p.Billing_Charge_Id__c, p.Id);
    }
    Map<Id, Id> entryByProduct = new Map<Id, Id>();
    for (PricebookEntry e : [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :std.Id AND Product2Id IN :productByCharge.values()]) {
        entryByProduct.put(e.Product2Id, e.Id);
    }
    List<PricebookEntry> newEntries = new List<PricebookEntry>();
    for (String charge : productByCharge.keySet()) {
        if (!entryByProduct.containsKey(productByCharge.get(charge))) {
            newEntries.add(new PricebookEntry(Pricebook2Id = std.Id, Product2Id = productByCharge.get(charge), UnitPrice = PRICES.get(charge), IsActive = true));
        }
    }
    insert newEntries;
    for (PricebookEntry e : newEntries) { entryByProduct.put(e.Product2Id, e.Id); }

    Map<String, Account> accounts = new Map<String, Account>();
    for (Account a : [SELECT Id, Name, Account_Key__c FROM Account WHERE Account_Key__c != null]) { accounts.put(a.Account_Key__c, a); }

    Id newBusiness = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('New_Business').getRecordTypeId();

    // key, stage, days until term end (null = term starts today), lines "charge:qty:discount", accept?
    List<List<Object>> deals = new List<List<Object>>{
        new List<Object>{ 'ACC-0001', 'Closed Won', 20, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:4:0,ZSIM-ONBOARD:1:0', true },
        new List<Object>{ 'ACC-0002', 'Closed Won', 45, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:2:0,ZSIM-PORTAL:1:0', true },
        new List<Object>{ 'ACC-0003', 'Closed Won', 75, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:6:10,ZSIM-ANALYTICS:1:0', true },
        new List<Object>{ 'ACC-0004', 'Closed Won', 200, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:8:5,ZSIM-ECLAIMS:1000:0', true },
        new List<Object>{ 'ACC-0005', 'Closed Won', 300, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:3:0', true },
        new List<Object>{ 'ACC-0006', 'Closed Won', null, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:12:0,ZSIM-ONBOARD:1:0', true },
        new List<Object>{ 'ACC-0007', 'Negotiation/Review', null, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:5:20', false },
        new List<Object>{ 'ACC-0008', 'Proposal/Price Quote', null, 'ZSIM-PLAT-BASE:1:0,ZSIM-PROV-SEAT:2:0', false },
        new List<Object>{ 'ACC-0009', 'Prospecting', null, '', false }
    };

    List<Opportunity> opps = new List<Opportunity>();
    for (List<Object> d : deals) {
        Account a = accounts.get((String) d[0]);
        Integer days = (Integer) d[2];
        opps.add(new Opportunity(
            Name = a.Name + ' - New Business', AccountId = a.Id, RecordTypeId = newBusiness, StageName = (String) d[1],
            CloseDate = days == null ? Date.today().addDays(21) : Date.today().addDays(days + 1).addMonths(-12),
            Pricebook2Id = std.Id, Description = MARK
        ));
    }
    insert opps;

    List<Quote> quotes = new List<Quote>();
    List<List<Object>> quotedDeals = new List<List<Object>>();
    for (Integer i = 0; i < deals.size(); i++) {
        List<Object> d = deals[i];
        if (String.isBlank((String) d[3])) { continue; }
        Integer days = (Integer) d[2];
        quotes.add(new Quote(
            Name = opps[i].Name + ' Quote', OpportunityId = opps[i].Id, Pricebook2Id = std.Id, Status = 'Draft',
            Term_Months__c = 12,
            Term_Start_Date__c = days == null ? Date.today() : Date.today().addDays(days + 1).addMonths(-12),
            ExpirationDate = Date.today().addDays(30)
        ));
        quotedDeals.add(d);
    }
    insert quotes;

    List<QuoteLineItem> lines = new List<QuoteLineItem>();
    for (Integer i = 0; i < quotes.size(); i++) {
        for (String spec : ((String) quotedDeals[i][3]).split(',')) {
            List<String> parts = spec.split(':');
            Id productId = productByCharge.get(parts[0]);
            lines.add(new QuoteLineItem(QuoteId = quotes[i].Id, PricebookEntryId = entryByProduct.get(productId),
                Quantity = Decimal.valueOf(parts[1]), UnitPrice = PRICES.get(parts[0]), Discount = Decimal.valueOf(parts[2])));
        }
    }
    insert lines;

    // Northgate: a sync that already exhausted its retries (rate limited). Demo step 4 retries it live.
    Quote northgate;
    Quote willow;
    for (Integer i = 0; i < quotes.size(); i++) {
        if (quotedDeals[i][0] == 'ACC-0006') { northgate = quotes[i]; }
        if (quotedDeals[i][0] == 'ACC-0007') { willow = quotes[i]; }
    }
    Integration_Log__c exhausted = new Integration_Log__c(
        External_Event_Key__c = 'SF:QUOTE_SYNC:' + northgate.Id, Event_Type__c = 'quote.sync', Direction__c = 'Outbound',
        Source_System__c = 'Salesforce', Target_System__c = 'Zuora (Simulated)', Correlation_Id__c = UUID.randomUUID().toString(),
        Related_Quote__c = northgate.Id, Related_Account__c = accounts.get('ACC-0006').Id, Status__c = 'Exhausted',
        Attempt_Count__c = 3, HTTP_Status__c = 429, Error_Category__c = 'Rate Limit',
        Sanitized_Error__c = 'Rate Limit: Too many requests, retry later (simulated)', Last_Attempt_At__c = System.now().addHours(-2)
    );
    insert exhausted;

    // Accept the closed-won quotes in one DML: the trigger queues one sync job (Northgate is skipped: its key exists).
    List<Quote> toAccept = new List<Quote>();
    for (Integer i = 0; i < quotes.size(); i++) {
        if ((Boolean) quotedDeals[i][4]) { toAccept.add(new Quote(Id = quotes[i].Id, Status = 'Accepted')); }
    }
    update toAccept;
    update new Quote(Id = northgate.Id, Billing_Sync_Status__c = 'Failed', Last_Sync_Log__c = exhausted.Id);

    // Willow Creek: 20% discount, above the 15% threshold -> submitted for manager approval.
    List<User> managers = [SELECT Id FROM User WHERE Alias = 'mmgr' AND IsActive = true LIMIT 1];
    Approval.ProcessSubmitRequest submit = new Approval.ProcessSubmitRequest();
    submit.setObjectId(willow.Id);
    submit.setComments('20% provider-seat discount to match a competing offer.');
    submit.setNextApproverIds(new List<Id>{ managers.isEmpty() ? UserInfo.getUserId() : managers[0].Id });
    Approval.process(submit);

    System.debug('SEED1: ' + opps.size() + ' opportunities, ' + quotes.size() + ' quotes, ' + toAccept.size() + ' accepted');
}
