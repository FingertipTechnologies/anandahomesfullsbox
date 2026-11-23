/**
 * @description Prevents further business edits after a booking swap is complete.
 *              The lock is logical: approval, swap cleanup, and financial recalculation
 *              remain allowed through explicit system fields or the transaction bypass.
 */
public with sharing class BookingSwapLockService {

    public static Boolean bypass = false;

    private static final Set<String> SYSTEM_EDITABLE_FIELDS = new Set<String>{
        'pending_amount__c',
        'total_receipt_amount__c',
        'total_base_amount__c',
        'total_base_paid__c',
        'total_gst_paid__c',
        'total_base_pending__c',
        'total_gst_pending__c'
    };

    public static void validateLockedBookingEdits(
        List<Booking__c> newList,
        Map<Id, Booking__c> oldMap
    ) {
        if (bypass || newList == null || oldMap == null) return;

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Booking__c.fields.getMap();

        for (Booking__c booking : newList) {
            Booking__c oldBooking = oldMap.get(booking.Id);
            if (oldBooking == null) continue;

            if (oldBooking.Is_Swapped__c != true) continue;

            for (String fieldName : fieldMap.keySet()) {
                String normalizedFieldName = fieldName.toLowerCase();
                if (SYSTEM_EDITABLE_FIELDS.contains(normalizedFieldName)) continue;

                Schema.SObjectField field = fieldMap.get(fieldName);
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (!describe.isUpdateable()) continue;

                Object oldValue = oldBooking.get(fieldName);
                Object newValue = booking.get(fieldName);
                if (valuesDiffer(oldValue, newValue)) {
                    booking.addError(
                        'This booking has been swapped and is locked. Further booking edits are not allowed.'
                    );
                    break;
                }
            }
        }
    }

    /**
     * Blocks insert/update/delete of business child records belonging to a swapped booking.
     * Trusted swap and post-swap cleanup bypass this service through {@code bypass}.
     */
    public static void validateLockedRelatedRecords(
        List<SObject> records,
        String objectLabel
    ) {
        if (bypass || records == null || records.isEmpty()) return;

        Set<Id> bookingIds = new Set<Id>();
        for (SObject record : records) {
            Id bookingId = (Id) record.get('Booking__c');
            if (bookingId != null) bookingIds.add(bookingId);
        }
        if (bookingIds.isEmpty()) return;

        Set<Id> swappedBookingIds = new Set<Id>();
        for (Booking__c booking : [
            SELECT Id
            FROM Booking__c
            WHERE Id IN :bookingIds AND Is_Swapped__c = TRUE
        ]) {
            swappedBookingIds.add(booking.Id);
        }
        if (swappedBookingIds.isEmpty()) return;

        for (SObject record : records) {
            Id bookingId = (Id) record.get('Booking__c');
            if (bookingId != null && swappedBookingIds.contains(bookingId)) {
                record.addError(
                    'This ' + objectLabel
                    + ' cannot be changed because its booking has been swapped.'
                );
            }
        }
    }

    public static void validateLockedRelatedRecords(
        List<SObject> records,
        List<SObject> oldRecords,
        String objectLabel
    ) {
        if (bypass || records == null || records.isEmpty()) return;

        Set<Id> bookingIds = new Set<Id>();
        for (SObject record : records) {
            Id bookingId = (Id) record.get('Booking__c');
            if (bookingId != null) bookingIds.add(bookingId);
        }
        if (oldRecords != null) {
            for (SObject record : oldRecords) {
                Id bookingId = (Id) record.get('Booking__c');
                if (bookingId != null) bookingIds.add(bookingId);
            }
        }
        if (bookingIds.isEmpty()) return;

        Set<Id> swappedBookingIds = new Set<Id>();
        for (Booking__c booking : [
            SELECT Id
            FROM Booking__c
            WHERE Id IN :bookingIds AND Is_Swapped__c = TRUE
        ]) {
            swappedBookingIds.add(booking.Id);
        }

        if (swappedBookingIds.isEmpty()) return;

        for (Integer i = 0; i < records.size(); i++) {
            Id currentBookingId = (Id) records[i].get('Booking__c');
            Id previousBookingId = oldRecords != null && i < oldRecords.size()
                ? (Id) oldRecords[i].get('Booking__c')
                : null;
            if ((currentBookingId != null && swappedBookingIds.contains(currentBookingId))
                || (previousBookingId != null && swappedBookingIds.contains(previousBookingId))) {
                records[i].addError(
                    'This ' + objectLabel
                    + ' cannot be changed because its booking has been swapped.'
                );
            }
        }
    }

    private static Boolean valuesDiffer(Object oldValue, Object newValue) {
        if (oldValue == null && newValue == null) return false;
        if (oldValue == null || newValue == null) return true;
        return JSON.serialize(oldValue) != JSON.serialize(newValue);
    }
}