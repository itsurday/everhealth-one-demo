/**
 * Opportunity queries for user-driven paths (USER_MODE: respects the running user's access).
 */
public inherited sharing class OpportunitySelector {
    public static Opportunity byId(Id opportunityId) {
        return [SELECT Id, Name FROM Opportunity WHERE Id = :opportunityId WITH USER_MODE LIMIT 1];
    }
}
