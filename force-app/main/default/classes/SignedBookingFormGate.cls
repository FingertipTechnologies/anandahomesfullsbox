/**
 * @description BRD §12A: after a First Applicant Change (FAC) is approved, the booking is on hold
 *              until the new first applicant's signed Booking Form is uploaded to the booking.
 *
 *              A booking is ON HOLD when "Signed Booking Form Uploaded" is false and it has an
 *              applied FAC whose "New Booking Form Uploaded" is still false (the approval resets the
 *              checkbox, see FirstApplicantChangeService). While on hold (user, 2026-11-20):
 *                • the booking's stage (Status__c) cannot change,
 *                • no demand, receipt, NOC or further FAC can be created for it,
 *                • no approval can be submitted for it (DynamicApprovalController).
 *
 *              The hold is lifted only by a NEW file: "Signed Booking Form Uploaded" may turn true
 *              only when a file of Document Type "Signed Booking Form" was uploaded to the booking
 *              after the FAC was approved (ticking the box by hand, or the old form, is refused).
 *              The FAC is then marked "New Booking Form Uploaded".
 *
 *              Runs without sharing / in system mode: the check must hold for every user.
 */
public without sharing class SignedBookingFormGate {

    public static final String SIGNED_FORM_TYPE = 'Signed Booking Form';

    /** The approved FAC holding each booking, for the bookings that are on hold. */
    public static Map<Id, First_Applicant_Change__c> holdingChanges(Set<Id> bookingIds) {
        Map<Id, First_Applicant_Change__c> result = new Map<Id, First_Applicant_Change__c>();
        if (bookingIds == null || bookingIds.isEmpty()) return result;
        Set<Id> unsigned = new Set<Id>();
        for (Booking__c b : [
            SELECT Id FROM Booking__c
            WHERE Id IN :bookingIds AND Signed_Booking_Form_Uploaded__c = false
        ]) {
            unsigned.add(b.Id);
        }
        result.putAll(pendingChangesFor(unsigned));
        return result;
    }

    /** Latest applied FAC per booking whose new signed form has not been uploaded yet. */
    private static Map<Id, First_Applicant_Change__c> pendingChangesFor(Set<Id> bookingIds) {
        Map<Id, First_Applicant_Change__c> result = new Map<Id, First_Applicant_Change__c>();
        if (bookingIds.isEmpty()) return result;
        for (First_Applicant_Change__c fac : [
            SELECT Id, Name, Booking__c, New_First_Applicant_Name__c, Applied_Date__c
            FROM First_Applicant_Change__c
            WHERE Booking__c IN :bookingIds AND Applied__c = true AND New_Booking_Form_Uploaded__c = false
            ORDER BY Applied_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (!result.containsKey(fac.Booking__c)) result.put(fac.Booking__c, fac);
        }
        return result;
    }

    @TestVisible
    private static String holdMessage(First_Applicant_Change__c fac, String action) {
        String applicant = String.isBlank(fac.New_First_Applicant_Name__c) ? 'the new first applicant'
            : fac.New_First_Applicant_Name__c;
        return 'This booking is on hold after First Applicant Change ' + fac.Name
            + ': upload the Booking Form signed by ' + applicant
            + ' to the booking (Document Type "' + SIGNED_FORM_TYPE + '") before ' + action + '.';
    }

    /**
     * Before insert of a child record (Demand, Receipt, NOC, FAC): refuses rows whose booking is
     * on hold. Rows without a booking are left alone.
     */
    public static void blockChildRecords(List<SObject> records, String action) {
        Set<Id> bookingIds = new Set<Id>();
        for (SObject r : records) {
            Id bookingId = (Id) r.get('Booking__c');
            if (bookingId != null) bookingIds.add(bookingId);
        }
        Map<Id, First_Applicant_Change__c> held = holdingChanges(bookingIds);
        if (held.isEmpty()) return;
        for (SObject r : records) {
            First_Applicant_Change__c fac = held.get((Id) r.get('Booking__c'));
            if (fac != null) r.addError(holdMessage(fac, action));
        }
    }

    /** For approval submission: throws when the record (a Booking, or a record of one) is on hold. */
    public static void assertNotOnHold(Id recordId, String action) {
        Id bookingId = bookingOf(recordId);
        if (bookingId == null) return;
        First_Applicant_Change__c fac = holdingChanges(new Set<Id>{ bookingId }).get(bookingId);
        if (fac != null) {
            AuraHandledException e = new AuraHandledException(holdMessage(fac, action));
            e.setMessage(holdMessage(fac, action));
            throw e;
        }
    }

    @TestVisible
    private static Id bookingOf(Id recordId) {
        if (recordId == null) return null;
        Schema.SObjectType sot = recordId.getSObjectType();
        if (sot == Booking__c.SObjectType) return recordId;
        Schema.SObjectField f = sot.getDescribe().fields.getMap().get('booking__c');
        if (f == null || !f.getDescribe().getReferenceTo().contains(Booking__c.SObjectType)) return null;
        List<SObject> rows = Database.query(
            'SELECT Booking__c FROM ' + sot.getDescribe().getName() + ' WHERE Id = :recordId LIMIT 1'
        );
        return rows.isEmpty() ? null : (Id) rows[0].get('Booking__c');
    }

    /**
     * Booking before update:
     *  - the stage cannot change while the booking is on hold;
     *  - "Signed Booking Form Uploaded" can turn true only with a signed form uploaded after the
     *    FAC approval.
     */
    public static void validateBookingUpdates(List<Booking__c> newList, Map<Id, Booking__c> oldMap) {
        Set<Id> candidates = new Set<Id>();
        for (Booking__c b : newList) {
            Booking__c old = oldMap.get(b.Id);
            Boolean stageChange = b.Status__c != old.Status__c && b.Signed_Booking_Form_Uploaded__c != true;
            Boolean unlocking = b.Signed_Booking_Form_Uploaded__c == true && old.Signed_Booking_Form_Uploaded__c != true;
            if (stageChange || unlocking) candidates.add(b.Id);
        }
        if (candidates.isEmpty()) return;
        Map<Id, First_Applicant_Change__c> pending = pendingChangesFor(candidates);
        if (pending.isEmpty()) return;
        Map<Id, Datetime> newestForm = newestSignedFormDates(pending.keySet());

        for (Booking__c b : newList) {
            First_Applicant_Change__c fac = pending.get(b.Id);
            if (fac == null) continue;
            Booking__c old = oldMap.get(b.Id);
            if (b.Signed_Booking_Form_Uploaded__c == true && old.Signed_Booking_Form_Uploaded__c != true) {
                Datetime uploaded = newestForm.get(b.Id);
                if (uploaded == null || (fac.Applied_Date__c != null && uploaded < fac.Applied_Date__c)) {
                    b.Signed_Booking_Form_Uploaded__c.addError('After First Applicant Change ' + fac.Name
                        + ', "Signed Booking Form Uploaded" is set by uploading the Booking Form signed by '
                        + (String.isBlank(fac.New_First_Applicant_Name__c) ? 'the new first applicant' : fac.New_First_Applicant_Name__c)
                        + ' (Document Type "' + SIGNED_FORM_TYPE + '"); the earlier form does not count.');
                }
            } else if (b.Status__c != old.Status__c) {
                b.Status__c.addError(holdMessage(fac, 'changing the booking stage'));
            }
        }
    }

    /** Booking after update: the new signed form is in, so mark the FAC as done. */
    public static void markNewFormUploaded(List<Booking__c> newList, Map<Id, Booking__c> oldMap) {
        Set<Id> unlocked = new Set<Id>();
        for (Booking__c b : newList) {
            if (b.Signed_Booking_Form_Uploaded__c == true && oldMap.get(b.Id).Signed_Booking_Form_Uploaded__c != true) {
                unlocked.add(b.Id);
            }
        }
        if (unlocked.isEmpty()) return;
        List<First_Applicant_Change__c> done = new List<First_Applicant_Change__c>();
        for (First_Applicant_Change__c fac : [
            SELECT Id FROM First_Applicant_Change__c
            WHERE Booking__c IN :unlocked AND Applied__c = true AND New_Booking_Form_Uploaded__c = false
        ]) {
            done.add(new First_Applicant_Change__c(Id = fac.Id, New_Booking_Form_Uploaded__c = true));
        }
        if (!done.isEmpty()) update done;
    }

    /** Upload time of the newest "Signed Booking Form" file on each booking. */
    private static Map<Id, Datetime> newestSignedFormDates(Set<Id> bookingIds) {
        Map<Id, Datetime> result = new Map<Id, Datetime>();
        Map<Id, Set<Id>> bookingsByDoc = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :bookingIds
        ]) {
            if (!bookingsByDoc.containsKey(link.ContentDocumentId)) bookingsByDoc.put(link.ContentDocumentId, new Set<Id>());
            bookingsByDoc.get(link.ContentDocumentId).add(link.LinkedEntityId);
        }
        if (bookingsByDoc.isEmpty()) return result;
        for (ContentVersion cv : [
            SELECT ContentDocumentId, CreatedDate FROM ContentVersion
            WHERE ContentDocumentId IN :bookingsByDoc.keySet() AND IsLatest = true
              AND Document_Type__c = :SIGNED_FORM_TYPE
        ]) {
            for (Id bookingId : bookingsByDoc.get(cv.ContentDocumentId)) {
                Datetime current = result.get(bookingId);
                if (current == null || cv.CreatedDate > current) result.put(bookingId, cv.CreatedDate);
            }
        }
        return result;
    }
}
