/**
 * Integration_Log__c queries. Runs in system mode on purpose: used only by the billing integration.
 */
public inherited sharing class IntegrationLogSelector {
    public static List<Integration_Log__c> byIds(Set<Id> ids) {
        return [
            SELECT Id, Status__c, Direction__c, Attempt_Count__c, External_Event_Key__c, Correlation_Id__c,
                Related_Quote__c, Related_Account__c, Duplicate_Count__c
            FROM Integration_Log__c
            WHERE Id IN :ids
            WITH SYSTEM_MODE
        ];
    }

    public static List<Integration_Log__c> byKeys(Set<String> keys) {
        return [
            SELECT Id, Status__c, External_Event_Key__c, Correlation_Id__c, Duplicate_Count__c
            FROM Integration_Log__c
            WHERE External_Event_Key__c IN :keys
            WITH SYSTEM_MODE
        ];
    }

    public static List<Integration_Log__c> dueForRetry(Datetime now, Integer maxRows) {
        return [
            SELECT Id, Status__c
            FROM Integration_Log__c
            WHERE Status__c = :RetryPolicy.RETRYABLE AND Next_Retry_At__c <= :now
            WITH SYSTEM_MODE
            ORDER BY Next_Retry_At__c
            LIMIT :maxRows
        ];
    }
}
