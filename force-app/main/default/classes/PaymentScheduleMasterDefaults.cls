/**
 * @description Flows master-level defaults onto a booking's Payment Schedule lines at creation.
 *              Copies the Master Payment Schedule's Is_Agreement and Include_Interest flags so the
 *              Agreement milestone and the interest-bearing milestones are tagged automatically
 *              however the schedule is generated (Apex or Flow).
 * @author System
 */
public with sharing class PaymentScheduleMasterDefaults {

    /** Escape hatch for trusted bulk / migration processes. */
    public static Boolean bypass = false;

    /**
     * @description For new payment-schedule lines linked to a Master Payment Schedule, copies the
     *              master's Is_Agreement__c and Include_Interest__c flags when the line is not
     *              already flagged.
     * @param newList Trigger.new (before insert)
     */
    public static void applyAgreementFlag(List<Payment_Schedule__c> newList) {
        if (bypass || newList == null || newList.isEmpty()) return;

        Set<Id> masterIds = new Set<Id>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Master_Payment_Schedule__c != null
                && (ps.Is_Agreement__c != true || ps.Include_Interest__c != true)) {
                masterIds.add(ps.Master_Payment_Schedule__c);
            }
        }
        if (masterIds.isEmpty()) return;

        Set<Id> agreementMasters = new Set<Id>();
        Set<Id> interestMasters = new Set<Id>();
        for (Master_Payment_Schedule__c ms : [
            SELECT Id, Is_Agreement__c, Include_Interest__c FROM Master_Payment_Schedule__c
            WHERE Id IN :masterIds AND (Is_Agreement__c = true OR Include_Interest__c = true)
        ]) {
            if (ms.Is_Agreement__c) agreementMasters.add(ms.Id);
            if (ms.Include_Interest__c) interestMasters.add(ms.Id);
        }
        if (agreementMasters.isEmpty() && interestMasters.isEmpty()) return;

        for (Payment_Schedule__c ps : newList) {
            if (ps.Master_Payment_Schedule__c == null) continue;
            if (agreementMasters.contains(ps.Master_Payment_Schedule__c)) ps.Is_Agreement__c = true;
            if (interestMasters.contains(ps.Master_Payment_Schedule__c)) ps.Include_Interest__c = true;
        }
    }
}
