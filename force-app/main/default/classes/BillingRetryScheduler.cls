/**
 * Auto-retry: re-queues Retryable Failure logs whose Next_Retry_At__c has passed.
 * without sharing: scheduled system job over integration logs owned by many users.
 */
public without sharing class BillingRetryScheduler implements Schedulable {
    public static final String JOB_NAME = 'EH Billing Auto-Retry';
    private static final List<Integer> MINUTES = new List<Integer>{ 0, 15, 30, 45 };

    public void execute(SchedulableContext context) {
        requeueDue();
    }

    /** Re-queues up to one chunk of due logs. Returns how many. */
    public static Integer requeueDue() {
        List<Integration_Log__c> due = IntegrationLogSelector.dueForRetry(System.now(), BillingSyncService.CHUNK_SIZE);
        if (due.isEmpty()) {
            return 0;
        }
        for (Integration_Log__c log : due) {
            log.Status__c = BillingSyncService.QUEUED;
        }
        Database.update(due, AccessLevel.SYSTEM_MODE);
        BillingSyncService.startJobs(new Map<Id, Integration_Log__c>(due).keySet());
        return due.size();
    }

    /** Apex cron has no minute step syntax, so every 15 minutes = four hourly jobs. Skips jobs already scheduled. */
    public static Integer scheduleEvery15Minutes() {
        Set<String> existing = new Set<String>();
        for (CronTrigger ct : [SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE :JOB_NAME + '%' WITH SYSTEM_MODE]) {
            existing.add(ct.CronJobDetail.Name);
        }
        Integer created = 0;
        for (Integer minute : MINUTES) {
            String name = JOB_NAME + ' :' + String.valueOf(minute).leftPad(2, '0');
            if (!existing.contains(name)) {
                System.schedule(name, '0 ' + minute + ' * * * ?', new BillingRetryScheduler());
                created++;
            }
        }
        return created;
    }
}
