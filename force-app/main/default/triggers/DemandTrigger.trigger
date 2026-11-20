/**
 * @description Trigger on Demands__c. On creation, populates the reminder cadence for the
 *              demand based on its Demand Type (BRD pointer 5):
 *                • Demand_Type__c = 'Agreement Amount' → Welcome Mail + 30 / 40 / 45 days.
 *                • any other demand type               → Demand Date + project configuration.
 *              This makes the reminder dates correct for every creation path (manual, bulk,
 *              auto), so the daily DemandReminderSchedulable can send them.
 * @author System
 */
trigger DemandTrigger on Demands__c (before insert, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        // On hold after a First Applicant Change until the new signed Booking Form is uploaded.
        SignedBookingFormGate.blockChildRecords(Trigger.new, 'raising a demand');
        DemandReminderService.populateReminderDates(Trigger.new);
        DemandReminderService.markCalculateFlag(Trigger.new);   // <-- added
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        DemandLineService.createForInsertedDemands(Trigger.new);
    }
}