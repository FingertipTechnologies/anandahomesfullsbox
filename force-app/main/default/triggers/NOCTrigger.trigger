/**
 * @description Trigger on NOC__c. Syncs the NOC's approval status onto its Booking
 *              (Booking__c.NOC_Approval_Status__c) on insert and when it changes.
 *              See NOCApprovalSyncService.
 * @author System
 */
trigger NOCTrigger on NOC__c (before insert, after insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        // On hold after a First Applicant Change until the new signed Booking Form is uploaded.
        SignedBookingFormGate.blockChildRecords(Trigger.new, 'raising a NOC');
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        NOCApprovalSyncService.syncToBooking(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
    }
}