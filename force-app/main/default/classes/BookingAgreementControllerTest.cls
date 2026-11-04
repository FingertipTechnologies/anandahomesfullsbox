@IsTest
private class BookingAgreementControllerTest {
    @IsTest
    static void loadsBookingAndRelatedLists() {
        Booking__c booking = postSalesTestDataFactory.createFullBooking('Agreement PDF Test');

        Test.startTest();
        BookingAgreementController extension = new BookingAgreementController(
            new ApexPages.StandardController(booking)
        );
        Test.stopTest();

        System.assertEquals(booking.Id, extension.booking.Id);
        System.assertEquals('Agreement PDF Test', extension.booking.Project__r.Name);
        System.assertEquals('tester@example.com', extension.booking.Email__c);
        String expectedFlatNumber = extension.booking.Flat_Number__c == null
            ? extension.booking.Plot__r.Name
            : String.valueOf(extension.booking.Flat_Number__c);
        if (expectedFlatNumber != null && expectedFlatNumber.endsWith('.0')) {
            expectedFlatNumber = expectedFlatNumber.substring(0, expectedFlatNumber.length() - 2);
        }
        System.assertEquals(
            expectedFlatNumber,
            extension.flatNumber
        );
        System.assertNotEquals(null, extension.receipts);
        System.assertNotEquals(null, extension.paymentSchedules);
        System.assertEquals(0, extension.receipts.size());
        System.assertEquals(0, extension.paymentSchedules.size());
    }
}