@IsTest
private class BookingQuoteFinancialFieldsTest {

    @IsTest
    static void quoteOwnsBookingGstAndTotalPayable() {
        Quote__c quote = new Quote__c(
            Saleable_Area_Sft__c = 1000,
            Price_Per_Sq_Ft__c = 100,
            GST1__c = 5
        );
        insert quote;

        Booking__c booking = new Booking__c(
            Quote__c = quote.Id,
            GST_Amount__c = 1,
            Total_Payable_Amount__c = 2
        );
        insert booking;

        quote = [SELECT GST_Amount__c, Total__c FROM Quote__c WHERE Id = :quote.Id];
        booking = [
            SELECT GST_Amount__c, Total_Payable_Amount__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        System.assertEquals(quote.GST_Amount__c, booking.GST_Amount__c);
        System.assertEquals(quote.Total__c, booking.Total_Payable_Amount__c);

        quote.Price_Per_Sq_Ft__c = 200;
        update quote;

        booking = [
            SELECT GST_Amount__c, Total_Payable_Amount__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        quote = [SELECT GST_Amount__c, Total__c FROM Quote__c WHERE Id = :quote.Id];
        System.assertEquals(quote.GST_Amount__c, booking.GST_Amount__c);
        System.assertEquals(quote.Total__c, booking.Total_Payable_Amount__c);

        booking.GST_Amount__c = 7;
        booking.Total_Payable_Amount__c = 8;
        update booking;

        booking = [
            SELECT GST_Amount__c, Total_Payable_Amount__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        System.assertEquals(quote.GST_Amount__c, booking.GST_Amount__c);
        System.assertEquals(quote.Total__c, booking.Total_Payable_Amount__c);
    }
}