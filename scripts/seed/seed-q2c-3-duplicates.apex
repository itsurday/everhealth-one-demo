// EverHealth One demo seed, part 3: duplicate scan after a bulk load.
// API/bulk loads don't create Duplicate Record Sets (the "Report" action only fires on UI saves), so this runs
// the org's active matching rules (Datacloud.FindDuplicates) over loaded Accounts/Contacts and records the
// matches for the EH_* duplicate rules. Idempotent: skips if EH duplicate record sets already exist.

if ([SELECT COUNT() FROM DuplicateRecordSet WHERE DuplicateRule.DeveloperName LIKE 'EH_%'] > 0) {
    System.debug('SEED3: duplicates already recorded, nothing to do');
} else {
    Map<String, Id> ruleIds = new Map<String, Id>();
    for (DuplicateRule r : [SELECT Id, DeveloperName FROM DuplicateRule WHERE DeveloperName LIKE 'EH_%']) {
        ruleIds.put(r.DeveloperName, r.Id);
    }
    // FindDuplicates accepts one object type per call (max 50 records).
    List<List<SObject>> batches = new List<List<SObject>>{
        [SELECT Id, Name, Website, Phone, BillingStreet, BillingCity, BillingPostalCode FROM Account WHERE Account_Key__c != null LIMIT 50],
        [SELECT Id, FirstName, LastName, Email, Phone, AccountId FROM Contact WHERE Contact_Key__c != null LIMIT 50]
    };
    Set<Id> grouped = new Set<Id>();
    List<DuplicateRecordSet> sets = new List<DuplicateRecordSet>();
    List<Set<Id>> members = new List<Set<Id>>();
    for (List<SObject> candidates : batches) {
        Datacloud.FindDuplicatesResult[] results = Datacloud.FindDuplicates.findDuplicates(candidates);
        for (Integer i = 0; i < results.size(); i++) {
            Id recordId = candidates[i].Id;
            for (Datacloud.DuplicateResult dr : results[i].getDuplicateResults()) {
                if (!ruleIds.containsKey(dr.getDuplicateRule()) || grouped.contains(recordId)) {
                    continue;
                }
                Set<Id> matchGroup = new Set<Id>{ recordId };
                for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                    for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                        matchGroup.add(rec.getRecord().Id);
                    }
                }
                if (matchGroup.size() > 1) {
                    grouped.addAll(matchGroup);
                    sets.add(new DuplicateRecordSet(DuplicateRuleId = ruleIds.get(dr.getDuplicateRule())));
                    members.add(matchGroup);
                }
            }
        }
    }
    insert sets;
    List<DuplicateRecordItem> items = new List<DuplicateRecordItem>();
    for (Integer i = 0; i < sets.size(); i++) {
        for (Id rid : members[i]) {
            items.add(new DuplicateRecordItem(DuplicateRecordSetId = sets[i].Id, RecordId = rid));
        }
    }
    insert items;
    System.debug('SEED3: ' + sets.size() + ' duplicate groups, ' + items.size() + ' records');
}
