/**
 * @description Applies an approved First Applicant Change to its Booking (BRD §12A).
 *
 *              On approval the booking's First Applicant name is updated and the
 *              "Signed Booking Form Uploaded" flag is reset to false, because a fresh Booking
 *              Form must be generated and re-signed by the new first applicant. Downstream
 *              stage progression is blocked (see BookingStageValidationService) until the new
 *              signed form is uploaded and marked on the change record.
 * @author System
 */
public with sharing class FirstApplicantChangeService {

    private static final String STATUS_APPROVED = 'Approved';

    /**
     * Other first-applicant details a change can carry (2026-11-18): Booking field -> the
     * "New ..." field on First_Applicant_Change__c. Filled values are copied to the booking on
     * approval; blank ones leave the booking value as it is. Order = order on the screen.
     */
    public static final List<String> DETAIL_BOOKING_FIELDS = new List<String>{
        'Salutation__c', 'S_o_D_o_W_o__c', 'Son_Daughter_Wife_of__c', 'Date_of_Birth__c',
        'PAN_Number__c', 'Aadhaar__c', 'Nationality__c', 'Residential_Status__c',
        'Marital_Status__c', 'Passport_PI_no__c', 'Occupation__c', 'Permanent_Address__c',
        'Correspondence_Address__c', 'Office_Address__c'
    };

    /** The First_Applicant_Change__c field holding the requested value for a booking field. */
    public static String changeFieldFor(String bookingField) {
        return 'New_' + bookingField;
    }

    /** Re-entrancy guard (the apply updates the change records themselves). */
    private static Boolean applying = false;

    /**
     * @description Stamps the Approved Date when status flips to Approved (before update).
     */
    public static void stampApprovalDate(List<First_Applicant_Change__c> newList, Map<Id, First_Applicant_Change__c> oldMap) {
        if (newList == null || oldMap == null) return;
        for (First_Applicant_Change__c fac : newList) {
            First_Applicant_Change__c old = oldMap.get(fac.Id);
            if (old == null) continue;
            if (STATUS_APPROVED.equalsIgnoreCase(fac.Approval_Status__c)
                && !STATUS_APPROVED.equalsIgnoreCase(old.Approval_Status__c)
                && fac.Approved_Date__c == null) {
                fac.Approved_Date__c = Date.today();
            }
        }
    }

    /**
     * @description Trigger entry point: detects changes newly flipped to Approved and applies them
     *              through the shared apply logic (also reachable from Flow via the invocable).
     */
    public static void applyApprovedChanges(List<First_Applicant_Change__c> newList, Map<Id, First_Applicant_Change__c> oldMap) {
        if (newList == null || oldMap == null) return;

        Set<Id> newlyApproved = new Set<Id>();
        for (First_Applicant_Change__c fac : newList) {
            First_Applicant_Change__c old = oldMap.get(fac.Id);
            if (old == null) continue;
            if (STATUS_APPROVED.equalsIgnoreCase(fac.Approval_Status__c)
                && !STATUS_APPROVED.equalsIgnoreCase(old.Approval_Status__c)) {
                newlyApproved.add(fac.Id);
            }
        }
        if (!newlyApproved.isEmpty()) {
            applyApproved(newlyApproved);
        }
    }

    /**
     * @description Flow-invocable entry point. Call this after the dynamic approval process approves
     *              a First Applicant Change to push the new details onto the booking.
     */
    @InvocableMethod(label='Apply First Applicant Change'
        description='Applies an approved First Applicant Change to its Booking: swaps the first applicant name/email/mobile, resets the signed booking form, links the previous change for history, and marks the change Applied.')
    public static void applyApprovedFromFlow(List<Id> changeIds) {
        if (changeIds == null) return;
        applyApproved(new Set<Id>(changeIds));
    }

    /**
     * @description Applies approved, not-yet-applied changes: updates the booking's first applicant
     *              name/email/mobile, resets the signed-form flag, captures history by linking the
     *              previously applied change (self-lookup), and stamps Applied / Applied Date.
     *              Idempotent — already-applied changes are skipped.
     */
    public static void applyApproved(Set<Id> changeIds) {
        if (applying || changeIds == null || changeIds.isEmpty()) return;

        List<String> detailFields = new List<String>();
        for (String bookingField : DETAIL_BOOKING_FIELDS) detailFields.add(changeFieldFor(bookingField));
        String approved = STATUS_APPROVED;
        List<First_Applicant_Change__c> changes = Database.query(
            'SELECT Id, Booking__c, Approval_Status__c, Applied__c, '
            + 'New_First_Applicant_Name__c, New_First_Applicant_Email__c, New_First_Applicant_Mobile__c, '
            + String.join(detailFields, ', ')
            + ' FROM First_Applicant_Change__c'
            + ' WHERE Id IN :changeIds AND Applied__c = false AND Approval_Status__c = :approved'
        );
        if (changes.isEmpty()) return;

        Set<Id> bookingIds = new Set<Id>();
        for (First_Applicant_Change__c fac : changes) {
            if (fac.Booking__c != null) bookingIds.add(fac.Booking__c);
        }

        // History: the most recent already-applied change per booking becomes the previous change.
        Map<Id, Id> latestAppliedByBooking = new Map<Id, Id>();
        for (First_Applicant_Change__c prior : [
            SELECT Id, Booking__c
            FROM First_Applicant_Change__c
            WHERE Booking__c IN :bookingIds AND Applied__c = true AND Id NOT IN :changeIds
            ORDER BY Applied_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (!latestAppliedByBooking.containsKey(prior.Booking__c)) {
                latestAppliedByBooking.put(prior.Booking__c, prior.Id);
            }
        }

        Map<Id, Booking__c> bookingsToUpdate = new Map<Id, Booking__c>();
        List<First_Applicant_Change__c> changesToUpdate = new List<First_Applicant_Change__c>();

        for (First_Applicant_Change__c fac : changes) {
            if (fac.Booking__c == null || String.isBlank(fac.New_First_Applicant_Name__c)) continue;

            Booking__c b = new Booking__c(Id = fac.Booking__c);
            b.First_Applicant_Name__c = fac.New_First_Applicant_Name__c;
            if (String.isNotBlank(fac.New_First_Applicant_Email__c)) b.Email__c = fac.New_First_Applicant_Email__c;
            if (String.isNotBlank(fac.New_First_Applicant_Mobile__c)) b.Mobile__c = fac.New_First_Applicant_Mobile__c;
            for (String bookingField : DETAIL_BOOKING_FIELDS) {
                Object value = fac.get(changeFieldFor(bookingField));
                if (value != null && String.isNotBlank(String.valueOf(value))) b.put(bookingField, value);
            }
            // Force a fresh signed Booking Form for the new applicant.
            b.Signed_Booking_Form_Uploaded__c = false;
            bookingsToUpdate.put(b.Id, b);

            First_Applicant_Change__c upd = new First_Applicant_Change__c(Id = fac.Id);
            upd.Applied__c = true;
            upd.Applied_Date__c = System.now();
            if (latestAppliedByBooking.containsKey(fac.Booking__c)) {
                upd.Previous_Change__c = latestAppliedByBooking.get(fac.Booking__c);
            }
            changesToUpdate.add(upd);
        }

        applying = true;
        try {
            if (!bookingsToUpdate.isEmpty()) update bookingsToUpdate.values();
            if (!changesToUpdate.isEmpty()) update changesToUpdate;
        } finally {
            applying = false;
        }
    }
}