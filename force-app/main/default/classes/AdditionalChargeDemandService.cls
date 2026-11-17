/**
 * @description Raises a Demands__c record for an Additional Charge (2026-11-17).
 *
 *              The "Additional Charge Demand Email" (Email_Template_Config__c on Additional_Charge__c)
 *              stamps Demand_Date__c = TODAY when it is sent. When a charge gets a Demand Date and has
 *              no live demand yet, one demand is created:
 *                - Demand_Type__c 'Additional Charge', Additional_Charge__c = the charge
 *                - amount = charge Amount + GST, paid/pending from the charge's Amount Paid
 *                - Reminder 1 = Demand Date + 15 days, Reminder 2 = Reminder 1 + 7 days (no 3rd/4th,
 *                  termination or unit unblocking); sent by DemandReminderService.
 *              Payments are recorded on the charge (Financial Transaction Manager), so every later
 *              change of the charge's amount / amount paid / status is copied onto its demand.
 * @author System
 */
public without sharing class AdditionalChargeDemandService {

    public static final String DEMAND_TYPE = 'Additional Charge';
    /** Escape hatch for data loads (and the tests of the charge-level reminder engine). */
    public static Boolean bypass = false;
    @TestVisible static final Integer REMINDER_1_DAYS = 15;
    @TestVisible static final Integer REMINDER_2_GAP_DAYS = 7;

    /** Before insert/update: a charge that is being demanded moves from Draft to Demanded. */
    public static void markDemanded(List<Additional_Charge__c> newList, Map<Id, Additional_Charge__c> oldMap) {
        for (Additional_Charge__c c : newList) {
            if (isBeingDemanded(c, oldMap) && (c.Status__c == null || c.Status__c == 'Draft')) {
                c.Status__c = 'Demanded';
            }
        }
    }

    /** After insert/update: create the demand for newly demanded charges, sync the others. */
    public static void handleAfterSave(List<Additional_Charge__c> newList, Map<Id, Additional_Charge__c> oldMap) {
        if (bypass) return;
        Set<Id> chargeIds = new Map<Id, Additional_Charge__c>(newList).keySet();
        Map<Id, Demands__c> demandByCharge = new Map<Id, Demands__c>();
        for (Demands__c d : [
            SELECT Id, Additional_Charge__c, Base_Amount__c, Demand_Amount__c, Paid_Amount__c, Pending_Amount__c, Status__c
            FROM Demands__c
            WHERE Additional_Charge__c IN :chargeIds AND Status__c != 'Cancelled'
            ORDER BY CreatedDate DESC
        ]) {
            if (!demandByCharge.containsKey(d.Additional_Charge__c)) {
                demandByCharge.put(d.Additional_Charge__c, d);
            }
        }

        List<Additional_Charge__c> toRaise = new List<Additional_Charge__c>();
        List<Demands__c> toUpdate = new List<Demands__c>();
        for (Additional_Charge__c c : newList) {
            Demands__c existing = demandByCharge.get(c.Id);
            if (existing == null) {
                if (isBeingDemanded(c, oldMap) && c.Booking__c != null && c.Status__c != 'Cancelled') {
                    toRaise.add(c);
                }
            } else if (applyChargeValues(existing, c)) {
                toUpdate.add(existing);
            }
        }
        if (!toRaise.isEmpty()) {
            insert buildDemands(toRaise);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static Boolean isBeingDemanded(Additional_Charge__c c, Map<Id, Additional_Charge__c> oldMap) {
        if (c.Demand_Date__c == null) {
            return false;
        }
        Additional_Charge__c old = oldMap == null ? null : oldMap.get(c.Id);
        return old == null || old.Demand_Date__c == null;
    }

    private static List<Demands__c> buildDemands(List<Additional_Charge__c> charges) {
        Set<Id> bookingIds = new Set<Id>();
        for (Additional_Charge__c c : charges) {
            bookingIds.add(c.Booking__c);
        }
        Map<Id, Booking__c> bookings = new Map<Id, Booking__c>([
            SELECT Id, Project__c FROM Booking__c WHERE Id IN :bookingIds
        ]);
        List<Demands__c> demands = new List<Demands__c>();
        for (Additional_Charge__c c : charges) {
            Date demandDate = c.Demand_Date__c;
            Date reminder1 = demandDate.addDays(REMINDER_1_DAYS);
            Booking__c b = bookings.get(c.Booking__c);
            Demands__c d = new Demands__c(
                Booking__c = c.Booking__c,
                Project__c = b == null ? null : b.Project__c,
                Additional_Charge__c = c.Id,
                Demand_Type__c = DEMAND_TYPE,
                Demand_Date__c = demandDate,
                Due_Date__c = c.Due_Date__c != null ? c.Due_Date__c : reminder1,
                Email_Sent__c = true,
                Email_Sent_Date__c = System.now(),
                Reminder_1_Date__c = reminder1,
                Reminder_2_Date__c = reminder1.addDays(REMINDER_2_GAP_DAYS),
                Notes__c = 'Additional charge: ' + (String.isBlank(c.Charge_Name__c) ? c.Name : c.Charge_Name__c)
            );
            applyChargeValues(d, c);
            if (d.Status__c == null) {
                d.Status__c = 'Emailed';
            }
            demands.add(d);
        }
        return demands;
    }

    /** Copies amount / paid / pending / status from the charge. Returns true when anything changed. */
    private static Boolean applyChargeValues(Demands__c d, Additional_Charge__c c) {
        Decimal total = nz(c.Amount__c) + nz(c.GST_Amount__c);
        Decimal paid = Math.min(nz(c.Amount_Paid__c), total);
        Decimal pending = Math.max(0, total - paid);
        Decimal base = nz(c.Amount__c); // Base Amount = the additional charge amount (2026-11-17)
        String status = d.Status__c;
        if (c.Status__c == 'Cancelled') {
            status = 'Cancelled';
        } else if (pending <= 0 && total > 0) {
            status = 'Paid';
        } else if (paid > 0) {
            status = 'Partially Paid';
        } else if (status == 'Paid' || status == 'Partially Paid') {
            status = 'Emailed';
        }
        Boolean changed = d.Demand_Amount__c != total || d.Paid_Amount__c != paid
            || d.Pending_Amount__c != pending || d.Status__c != status || d.Base_Amount__c != base;
        d.Base_Amount__c = base;
        d.Demand_Amount__c = total;
        d.Paid_Amount__c = paid;
        d.Pending_Amount__c = pending;
        d.Status__c = status;
        return changed;
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}
