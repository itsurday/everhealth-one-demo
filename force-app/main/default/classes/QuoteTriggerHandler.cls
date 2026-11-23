/**
 * Quote trigger logic. Only process owned here: Accepted transition -> billing sync (STA §4).
 */
public with sharing class QuoteTriggerHandler {
    public static final String ACCEPTED = 'Accepted';

    /** Acts only on records whose Status changed to Accepted, so re-saves don't re-sync. */
    public static void afterUpdate(List<Quote> newQuotes, Map<Id, Quote> oldQuotes) {
        Set<Id> acceptedIds = new Set<Id>();
        for (Quote q : newQuotes) {
            if (q.Status == ACCEPTED && oldQuotes.get(q.Id).Status != ACCEPTED) {
                acceptedIds.add(q.Id);
            }
        }
        BillingSyncService.enqueue(acceptedIds);
    }
}
