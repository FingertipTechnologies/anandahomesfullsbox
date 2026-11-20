/**
 * @description Trigger on First_Applicant_Change__c. Stamps the approval date and applies the
 *              approved change to the booking (BRD §12A).
 * @author System
 */
trigger FirstApplicantChangeTrigger on First_Applicant_Change__c (before insert, before update, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        // No second change while the booking waits for the previous change's signed Booking Form.
        SignedBookingFormGate.blockChildRecords(Trigger.new, 'raising another First Applicant Change');
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        FirstApplicantChangeService.stampApprovalDate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        FirstApplicantChangeService.applyApprovedChanges(Trigger.new, Trigger.oldMap);
    }
}