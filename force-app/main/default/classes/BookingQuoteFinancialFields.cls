public without sharing class BookingQuoteFinancialFields {

    public static void syncFromBookings(List<Booking__c> bookings) {
        Set<Id> quoteIds = new Set<Id>();
        for (Booking__c booking : bookings) {
            if (booking.Quote__c != null) {
                quoteIds.add(booking.Quote__c);
            }
        }
        if (quoteIds.isEmpty()) return;

        Map<Id, Quote__c> quotesById = new Map<Id, Quote__c>([
            SELECT Id, GST_Amount__c, Total__c
            FROM Quote__c
            WHERE Id IN :quoteIds
        ]);

        for (Booking__c booking : bookings) {
            Quote__c quote = quotesById.get(booking.Quote__c);
            if (quote == null) continue;

            booking.GST_Amount__c = quote.GST_Amount__c;
            booking.Total_Payable_Amount__c = quote.Total__c;
        }
    }

    public static void syncBookingsFromQuotes(List<Quote__c> quotes) {
        Set<Id> quoteIds = new Set<Id>();
        for (Quote__c quote : quotes) {
            quoteIds.add(quote.Id);
        }
        if (quoteIds.isEmpty()) return;

        List<Booking__c> bookingsToUpdate = new List<Booking__c>();
        for (Booking__c booking : [
            SELECT Id, Quote__c, Quote__r.GST_Amount__c, Quote__r.Total__c,
                   GST_Amount__c, Total_Payable_Amount__c
            FROM Booking__c
            WHERE Quote__c IN :quoteIds
        ]) {
            Decimal quoteGst = booking.Quote__r.GST_Amount__c;
            Decimal quoteTotal = booking.Quote__r.Total__c;
            if (booking.GST_Amount__c != quoteGst
                || booking.Total_Payable_Amount__c != quoteTotal) {
                booking.GST_Amount__c = quoteGst;
                booking.Total_Payable_Amount__c = quoteTotal;
                bookingsToUpdate.add(booking);
            }
        }

        if (!bookingsToUpdate.isEmpty()) {
            update bookingsToUpdate;
        }
    }
}