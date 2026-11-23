/**
 * Async callout context for one chunk of billing sync logs (see BillingSyncService.startJobs).
 * without sharing: runs the system integration process on behalf of whoever accepted the quote.
 */
public without sharing class BillingSyncQueueable implements Queueable, Database.AllowsCallouts {
    private final Set<Id> logIds;

    public BillingSyncQueueable(Set<Id> logIds) {
        this.logIds = logIds;
    }

    public void execute(QueueableContext context) {
        BillingSyncService.process(logIds);
    }
}
