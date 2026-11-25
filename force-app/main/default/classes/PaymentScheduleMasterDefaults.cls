/**
 * @description Flows master-level defaults onto a booking's Payment Schedule lines at creation.
 *              Currently copies the Master Payment Schedule's Is_Agreement flag so the Agreement
 *              milestone is tagged automatically however the schedule is generated (Apex or Flow).
 * @author System
 */
public with sharing class PaymentScheduleMasterDefaults {

    /** Escape hatch for trusted bulk / migration processes. */
    public static Boolean bypass = false;

    /**
     * @description For new payment-schedule lines linked to a Master Payment Schedule, copies the
     *              master's Is_Agreement__c flag when the line is not already flagged.
     * @param newList Trigger.new (before insert)
     */
    public static void applyAgreementFlag(List<Payment_Schedule__c> newList) {
        if (bypass || newList == null || newList.isEmpty()) return;

        Set<Id> masterIds = new Set<Id>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Master_Payment_Schedule__c != null && ps.Is_Agreement__c != true) {
                masterIds.add(ps.Master_Payment_Schedule__c);
            }
        }
        if (masterIds.isEmpty()) return;

        Set<Id> agreementMasters = new Set<Id>();
        for (Master_Payment_Schedule__c ms : [
            SELECT Id FROM Master_Payment_Schedule__c
            WHERE Id IN :masterIds AND Is_Agreement__c = true
        ]) {
            agreementMasters.add(ms.Id);
        }
        if (agreementMasters.isEmpty()) return;

        for (Payment_Schedule__c ps : newList) {
            if (ps.Master_Payment_Schedule__c != null
                && agreementMasters.contains(ps.Master_Payment_Schedule__c)) {
                ps.Is_Agreement__c = true;
            }
        }
    }

    /**
     * @description Include Interest is ticked on every milestone BELOW the booking's Agreement
     *              milestone (higher Sequence), and cleared on the Agreement milestone and those above it.
     *              Runs on insert, and on update when Sequence or the Agreement flag changes. A booking
     *              with no Agreement milestone is left as it is.
     * @param newList Trigger.new (before insert / before update)
     * @param oldMap  Trigger.oldMap (null on insert)
     */
    public static void applyInterestFlag(List<Payment_Schedule__c> newList, Map<Id, Payment_Schedule__c> oldMap) {
        if (bypass || newList == null || newList.isEmpty()) return;

        List<Payment_Schedule__c> toSet = new List<Payment_Schedule__c>();
        Set<Id> bookingIds = new Set<Id>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Booking__c == null) continue;
            Payment_Schedule__c old = oldMap == null ? null : oldMap.get(ps.Id);
            if (old != null && old.Sequence__c == ps.Sequence__c && old.Is_Agreement__c == ps.Is_Agreement__c) continue;
            toSet.add(ps);
            bookingIds.add(ps.Booking__c);
        }
        if (toSet.isEmpty()) return;

        // Agreement Sequence per booking: lines in this save win over what is already stored.
        Set<Id> inThisSave = new Set<Id>();
        Map<Id, Decimal> agreementSeq = new Map<Id, Decimal>();
        for (Payment_Schedule__c ps : newList) {
            if (ps.Id != null) inThisSave.add(ps.Id);
            if (ps.Booking__c != null && ps.Is_Agreement__c == true && ps.Sequence__c != null) {
                keepLowest(agreementSeq, ps.Booking__c, ps.Sequence__c);
            }
        }
        for (Payment_Schedule__c ps : [
            SELECT Booking__c, Sequence__c FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds AND Is_Agreement__c = true AND Sequence__c != null
            AND Id NOT IN :inThisSave
            WITH SYSTEM_MODE
        ]) {
            keepLowest(agreementSeq, ps.Booking__c, ps.Sequence__c);
        }

        for (Payment_Schedule__c ps : toSet) {
            Decimal agreement = agreementSeq.get(ps.Booking__c);
            if (agreement == null || ps.Sequence__c == null) continue;
            ps.Include_Interest__c = ps.Sequence__c > agreement;
        }
    }

    private static void keepLowest(Map<Id, Decimal> values, Id key, Decimal value) {
        if (!values.containsKey(key) || value < values.get(key)) values.put(key, value);
    }
}