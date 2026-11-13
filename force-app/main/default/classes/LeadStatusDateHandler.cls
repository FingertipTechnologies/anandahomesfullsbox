/**
 * Stamps Lead__c.Status_Change_Date__c whenever Lead_Status__c changes (before update).
 * Used by the home page "Lead's For The Day" tab to show when a lead was worked.
 */
public with sharing class LeadStatusDateHandler {
    public static void stampStatusChange(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        if (newLeads == null || oldMap == null) return;
        Datetime now = System.now();
        for (Lead__c ld : newLeads) {
            Lead__c old = oldMap.get(ld.Id);
            if (old != null && ld.Lead_Status__c != old.Lead_Status__c) {
                ld.Status_Change_Date__c = now;
            }
        }
    }
}