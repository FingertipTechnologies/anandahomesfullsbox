@IsTest
private class BookingAgreementControllerTest {
    @IsTest
    static void loadsBookingAndRelatedLists() {
        Booking__c booking = postSalesTestDataFactory.createFullBooking('Agreement PDF Test');
        insert new Co_Applicant__c(Booking__c = booking.Id, Full_Name__c = 'Co Buyer',
                                   Permenent_Address__c = 'Hyderabad', Email__c = 'co@example.com');

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
        // The booking flow may create the booking-amount receipt and the payment schedules,
        // so compare with what is actually on the booking.
        System.assertEquals([SELECT COUNT() FROM Receipt__c WHERE Booking__c = :booking.Id], extension.receipts.size());
        System.assertEquals([SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id], extension.paymentSchedules.size());
        System.assertEquals(1, extension.coApplicants.size());
        System.assertEquals('Co Buyer', extension.coApplicants[0].Full_Name__c);
    }
}