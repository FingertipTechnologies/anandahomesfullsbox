public without sharing class BookingUnitBookingValidationService {

    private static final Set<String> INACTIVE_STATUSES = new Set<String>{
        'Cancellation', 'Cancelled', 'Swapping', 'Swapped'
    };

    public static void validateOneActiveBookingPerUnit(List<Booking__c> bookings) {
        if (bookings == null || bookings.isEmpty()) {
            return;
        }

        Set<Id> unitIds = new Set<Id>();
        Set<Id> currentBookingIds = new Set<Id>();
        Map<Id, List<Booking__c>> activeBookingsByUnit = new Map<Id, List<Booking__c>>();

        for (Booking__c booking : bookings) {
            if (booking.Id != null) {
                currentBookingIds.add(booking.Id);
            }
            if (booking.Plot__c == null || isInactive(booking)) {
                continue;
            }

            unitIds.add(booking.Plot__c);
            if (!activeBookingsByUnit.containsKey(booking.Plot__c)) {
                activeBookingsByUnit.put(booking.Plot__c, new List<Booking__c>());
            }
            activeBookingsByUnit.get(booking.Plot__c).add(booking);
        }

        if (unitIds.isEmpty()) {
            return;
        }

        // Serialize assignments for each unit so concurrent transactions cannot both pass.
        List<Plot__c> lockedUnits = [
            SELECT Id
            FROM Plot__c
            WHERE Id IN :unitIds
            FOR UPDATE
        ];

        Set<Id> conflictingUnitIds = new Set<Id>();
        for (Id unitId : activeBookingsByUnit.keySet()) {
            if (activeBookingsByUnit.get(unitId).size() > 1) {
                conflictingUnitIds.add(unitId);
            }
        }

        for (Booking__c existingBooking : [
            SELECT Id, Plot__c
            FROM Booking__c
            WHERE Plot__c IN :unitIds
            AND Id NOT IN :currentBookingIds
            AND (Status__c = null OR Status__c NOT IN :INACTIVE_STATUSES)
            AND (Is_Swapped__c = false OR Is_Swapped__c = null)
        ]) {
            conflictingUnitIds.add(existingBooking.Plot__c);
        }

        for (Booking__c booking : bookings) {
            if (booking.Plot__c != null
                && !isInactive(booking)
                && conflictingUnitIds.contains(booking.Plot__c)) {
                booking.addError(
                    'This unit already has an active booking. A unit can have only one active booking; '
                    + 'cancel or swap the existing booking before assigning it again.'
                );
            }
        }
    }

    private static Boolean isInactive(Booking__c booking) {
        return INACTIVE_STATUSES.contains(booking.Status__c) || booking.Is_Swapped__c == true;
    }
}