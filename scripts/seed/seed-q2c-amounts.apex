// EverHealth One demo seed: annualized Opportunity.Amount from each opportunity's latest quote.
// Monthly recurring/usage lines x 12; annual and one-time lines once. Only fills blank amounts (idempotent).
Map<Id, Decimal> amountByOpp = new Map<Id, Decimal>();
for (QuoteLineItem li : [
    SELECT TotalPrice, Product2.Billing_Period__c, Quote.OpportunityId
    FROM QuoteLineItem
    WHERE Quote.Opportunity.Amount = null AND Quote.Opportunity.Account.Account_Key__c != null
]) {
    Decimal months = li.Product2.Billing_Period__c == 'Month' ? 12 : (li.Product2.Billing_Period__c == 'Quarter' ? 4 : 1);
    Id oppId = li.Quote.OpportunityId;
    amountByOpp.put(oppId, (amountByOpp.containsKey(oppId) ? amountByOpp.get(oppId) : 0) + li.TotalPrice * months);
}
List<Opportunity> opps = new List<Opportunity>();
for (Id oppId : amountByOpp.keySet()) {
    opps.add(new Opportunity(Id = oppId, Amount = amountByOpp.get(oppId).setScale(2)));
}
update opps;
System.debug('SEEDAMT: ' + opps.size() + ' opportunity amounts set');
