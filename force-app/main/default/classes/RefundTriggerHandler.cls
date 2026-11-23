/**
 * @description Refund__c trigger logic. A refund on a cancelled booking (Status = Cancellation) can
 *              only be created once the cancellation letter - any file of the "Cancellation"
 *              document category - is uploaded on the booking (user rule 2026-11-18). Applies to
 *              every way a refund is created: the Financial Transactions screen, the New button
 *              and imports.
 */
public with sharing class RefundTriggerHandler {
    /** Document category of the files that count as the cancellation letter. */
    public static final String CANCELLATION_DOCUMENT_CATEGORY = 'Cancellation';

    public static final String CANCELLATION_LETTER_REQUIRED =
        'Upload the cancellation letter on the booking (Documents, category "Cancellation") '
        + 'before creating a refund.';

    /**
     * @description The bookings among the given ones that have no file of the Cancellation
     *              document category attached (latest version of each file is checked).
     */
    public static Set<Id> withoutCancellationLetter(Set<Id> bookingIds) {
        Set<Id> missing = bookingIds == null ? new Set<Id>() : new Set<Id>(bookingIds);
        missing.remove(null);
        if (missing.isEmpty()) return missing;

        Map<Id, Set<Id>> bookingsByDocument = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :missing
            WITH SYSTEM_MODE
        ]) {
            if (!bookingsByDocument.containsKey(link.ContentDocumentId)) {
                bookingsByDocument.put(link.ContentDocumentId, new Set<Id>());
            }
            bookingsByDocument.get(link.ContentDocumentId).add(link.LinkedEntityId);
        }
        if (bookingsByDocument.isEmpty()) return missing;

        Set<Id> documentIds = bookingsByDocument.keySet();
        for (ContentVersion version : [
            SELECT ContentDocumentId FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
            AND IsLatest = true
            AND Document_Category__c = :CANCELLATION_DOCUMENT_CATEGORY
            WITH SYSTEM_MODE
        ]) {
            missing.removeAll(bookingsByDocument.get(version.ContentDocumentId));
        }
        return missing;
    }

    /**
     * @description Refund__c before insert: a refund on a cancelled booking (Status = Cancellation)
     *              needs the cancellation letter uploaded on the booking first.
     */
    public static void requireCancellationLetter(List<Refund__c> refunds) {
        Set<Id> bookingIds = new Set<Id>();
        for (Refund__c refund : refunds) {
            if (refund.Booking__c != null) bookingIds.add(refund.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        Set<Id> cancelledBookingIds = new Set<Id>();
        for (Booking__c booking : [
            SELECT Id FROM Booking__c
            WHERE Id IN :bookingIds AND Status__c = 'Cancellation'
            WITH SYSTEM_MODE
        ]) {
            cancelledBookingIds.add(booking.Id);
        }
        Set<Id> missing = withoutCancellationLetter(cancelledBookingIds);
        for (Refund__c refund : refunds) {
            if (missing.contains(refund.Booking__c)) {
                refund.addError(CANCELLATION_LETTER_REQUIRED);
            }
        }
    }
}