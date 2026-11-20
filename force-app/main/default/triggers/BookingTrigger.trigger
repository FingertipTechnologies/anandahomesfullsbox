/**
* @description The BookingTrigger.
* @author : Arun Kumar N
* @createdDate : 21/12/2025
* @status : Active trigger
*
* After-context handlers added to capture stage-wise remarks (BRD pointer 1).
*/
trigger BookingTrigger on Booking__c (before insert, before update, after insert, after update) {
    if(label.BookingTriggerActive == 'True'){
        
        
        if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
            BookingUnitBookingValidationService.validateOneActiveBookingPerUnit(Trigger.new);

            //Stage-progression gates (BRD lifecycle prerequisites).
            if (Trigger.isUpdate) {
                // After a First Applicant Change: no stage change until the new signed Booking Form
                // is uploaded, and the "uploaded" checkbox only turns true with that new file.
                SignedBookingFormGate.validateBookingUpdates(Trigger.new, Trigger.oldMap);
                BookingStageValidationService.validateStageTransitions(Trigger.new, Trigger.oldMap);
            }
        }
        
        if (Trigger.isAfter) {
            if (Trigger.isInsert) {
                BookingStageRemarkService.captureForNewBookings(Trigger.new);
            } else if (Trigger.isUpdate) {
                BookingStageRemarkService.captureForStageChanges(Trigger.new, Trigger.oldMap);
                // Swap request rejected -> reject its auto-created quote (frees the unit).
                SwapQuoteService.handleBookingUpdate(Trigger.new, Trigger.oldMap);
                SignedBookingFormGate.markNewFormUploaded(Trigger.new, Trigger.oldMap);
            }
        }
    }
}