public with sharing class InterestWaiverService {

    public static Map<Id, Decimal> getRemainingWaivers(Set<Id> bookingIds) {
        return getRemainingWaivers(bookingIds, false);
    }

    public static Map<Id, Decimal> getRemainingWaivers(Set<Id> bookingIds, Boolean lockBookings) {
        Map<Id, Decimal> remainingByBooking = new Map<Id, Decimal>();
        if (bookingIds == null || bookingIds.isEmpty()) {
            return remainingByBooking;
        }

        List<Booking__c> bookings = lockBookings == true
            ? [SELECT Id, Total_Interest_Waive_Off__c FROM Booking__c WHERE Id IN :bookingIds FOR UPDATE]
            : [SELECT Id, Total_Interest_Waive_Off__c FROM Booking__c WHERE Id IN :bookingIds];
        for (Booking__c booking : bookings) {
            remainingByBooking.put(
                booking.Id,
                booking.Total_Interest_Waive_Off__c == null ? 0 : booking.Total_Interest_Waive_Off__c
            );
        }

        for (AggregateResult result : [
            SELECT Booking__c bookingId, SUM(Interest_Waived_Off_Amount__c) appliedAmount
            FROM Demands__c
            WHERE Booking__c IN :bookingIds
            GROUP BY Booking__c
        ]) {
            Id bookingId = (Id) result.get('bookingId');
            Decimal approved = remainingByBooking.containsKey(bookingId)
                ? remainingByBooking.get(bookingId)
                : 0;
            Decimal applied = result.get('appliedAmount') == null
                ? 0
                : (Decimal) result.get('appliedAmount');
            remainingByBooking.put(bookingId, Math.max(0, approved - applied));
        }

        return remainingByBooking;
    }

    public static Decimal getWaiverAmount(Decimal grossInterest, Decimal remainingWaiver) {
        Decimal interest = grossInterest == null ? 0 : grossInterest;
        Decimal remaining = remainingWaiver == null ? 0 : remainingWaiver;
        return Math.min(Math.max(0, interest), Math.max(0, remaining));
    }
}